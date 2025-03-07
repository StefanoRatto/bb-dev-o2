#!/bin/bash

# ============================================================================
# BB-DEV-O2 RUNNER - Main orchestration script for the BB-DEV-O2 framework
# 
# This script continuously runs and schedules workflows at specific intervals.
# It handles both hourly and daily workflows, launching them as background
# processes at the appropriate times.
#
# Version: 2.0.0
# ============================================================================

# Set strict error handling
set -o errexit  # Exit on error
set -o pipefail # Exit if any command in a pipe fails
set -o nounset  # Exit on undefined variables

# Define home folder and paths
home=$(pwd)
home_daily=$home/workflows/daily/
home_hourly=$home/workflows/hourly/
log_dir="$home/logs"
log_file="$log_dir/runner.log"
config_file="$home/.bb-dev-o2_config"
templates_dir="$home/templates"
pid_file="$home/runner.pid"

# Create necessary directories
mkdir -p "$log_dir"
mkdir -p "$home/outputs"
mkdir -p "$templates_dir"

# Define time stamp function for consistent timestamps
get_timestamp() {
  $home/now.sh
}

# Function to handle script termination
cleanup() {
    local exit_code=$?
    log_message "Shutting down BB-DEV-O2 runner (exit code: $exit_code)"
    
    # Kill any child processes
    if [ -n "${child_pids:-}" ]; then
        for pid in "${child_pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                log_message "Terminating child process $pid"
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
    fi
    
    # Remove PID file
    if [ -f "$pid_file" ]; then
        rm -f "$pid_file"
    fi
    
    log_message "BB-DEV-O2 runner shutdown complete"
    exit $exit_code
}

# Set up trap for clean exit
trap cleanup EXIT INT TERM

# Check if already running
if [ -f "$pid_file" ]; then
    pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
        echo "BB-DEV-O2 runner is already running with PID $pid"
        exit 1
    else
        log_message "Removing stale PID file"
        rm -f "$pid_file"
    fi
fi

# Write current PID to file
echo $$ > "$pid_file"

# Initialize log file if it doesn't exist
if [ ! -f "$log_file" ]; then
    touch "$log_file"
    echo "[$(get_timestamp)] Log file initialized" >> "$log_file"
fi

# Function to log messages to both console and log file with severity
log_message() {
    local message="$1"
    local severity="${2:-INFO}"
    local timestamp=$(get_timestamp)
    local log_entry="[$timestamp] [$severity] $message"
    
    # Color output based on severity
    if [ -t 1 ]; then  # Check if stdout is a terminal
        case "$severity" in
            ERROR)   echo -e "\033[0;31m$log_entry\033[0m" ;;  # Red
            WARNING) echo -e "\033[0;33m$log_entry\033[0m" ;;  # Yellow
            SUCCESS) echo -e "\033[0;32m$log_entry\033[0m" ;;  # Green
            *)       echo "$log_entry" ;;                      # Default
        esac
    else
        echo "$log_entry"
    fi
    
    echo "$log_entry" >> "$log_file"
}

# Function to check system resources
check_system_resources() {
    # Check CPU load
    local cpu_load=$(awk '{print $1}' /proc/loadavg)
    local cpu_cores=$(nproc)
    local cpu_threshold=$(echo "$cpu_cores * 0.8" | bc)
    
    if (( $(echo "$cpu_load > $cpu_threshold" | bc -l) )); then
        log_message "High CPU load detected: $cpu_load (threshold: $cpu_threshold)" "WARNING"
        return 1
    fi
    
    # Check memory usage
    local mem_available=$(grep 'MemAvailable' /proc/meminfo | awk '{print $2}')
    local mem_total=$(grep 'MemTotal' /proc/meminfo | awk '{print $2}')
    local mem_percent=$(echo "scale=2; ($mem_total - $mem_available) / $mem_total * 100" | bc)
    
    if (( $(echo "$mem_percent > 90" | bc -l) )); then
        log_message "High memory usage detected: ${mem_percent}%" "WARNING"
        return 1
    fi
    
    # Check disk space
    local disk_usage=$(df -h . | awk 'NR==2 {print $5}' | tr -d '%')
    
    if [ "$disk_usage" -gt 90 ]; then
        log_message "Low disk space detected: ${disk_usage}%" "WARNING"
        return 1
    fi
    
    return 0
}

# Function to run a workflow with proper error handling and resource management
run_workflow() {
    local workflow_file="$1"
    local workflow_name=$(basename "$workflow_file")
    local priority="${2:-normal}"
    
    # Check if system resources are sufficient
    if ! check_system_resources; then
        if [ "$priority" = "high" ]; then
            log_message "Running high-priority workflow $workflow_name despite resource constraints" "WARNING"
        else
            log_message "Skipping workflow $workflow_name due to resource constraints" "WARNING"
            return 1
        fi
    fi
    
    # Create a dedicated log file for this workflow run
    local timestamp=$(get_timestamp)
    local workflow_log="$log_dir/${workflow_name}_${timestamp}.log"
    
    log_message "Starting workflow: $workflow_name" "INFO"
    
    # Set resource limits based on priority
    local nice_level=10
    local ionice_class=2
    local ionice_level=7
    
    if [ "$priority" = "high" ]; then
        nice_level=0
        ionice_class=1
        ionice_level=0
    fi
    
    # Run the workflow in background with resource limits and redirect output to its log file
    nice -n $nice_level ionice -c $ionice_class -n $ionice_level bash "$workflow_file" > "$workflow_log" 2>&1 &
    local pid=$!
    
    # Add to child PIDs array for cleanup
    child_pids+=("$pid")
    
    log_message "Launched $workflow_name with PID $pid (priority: $priority)" "SUCCESS"
    
    # Add to process tracking file for monitoring
    echo "$pid:$workflow_name:$timestamp:$priority" >> "$log_dir/active_processes.log"
    
    return 0
}

# Function to check if a workflow should run
should_run_workflow() {
    local file="$1"
    local ext="${file##*.}"
    local filename="$(basename "$file")"
    
    # Only run .sh files that start with "workflow" and don't start with "_"
    if [ "$ext" == "sh" ] && [[ "$filename" == workflow* ]] && [[ "$filename" != _* ]]; then
        # Check if the file is executable
        if [ -x "$file" ]; then
            return 0  # True
        else
            log_message "Workflow file is not executable: $file" "WARNING"
            chmod +x "$file"
            return 0  # True
        fi
    else
        return 1  # False
    fi
}

# Function to clean up old log files with rotation
cleanup_old_logs() {
    # Keep last 7 days of logs
    find "$log_dir" -type f -name "*.log" -mtime +7 -delete
    
    # Compress logs older than 1 day
    find "$log_dir" -type f -name "*.log" -mtime +1 -not -name "*.gz" -exec gzip {} \;
    
    # Count removed and compressed files
    local removed=$(find "$log_dir" -type f -name "*.log" -mtime +7 | wc -l)
    local compressed=$(find "$log_dir" -type f -name "*.log.gz" | wc -l)
    
    log_message "Log rotation complete: removed $removed old logs, compressed $compressed logs" "INFO"
}

# Function to monitor running processes
monitor_processes() {
    if [ ! -f "$log_dir/active_processes.log" ]; then
        return
    fi
    
    local current_time=$(date +%s)
    local zombie_count=0
    local running_count=0
    
    while IFS=: read -r pid name timestamp priority; do
        if [ -z "$pid" ]; then
            continue
        fi
        
        # Check if process is still running
        if kill -0 "$pid" 2>/dev/null; then
            running_count=$((running_count + 1))
            
            # Check if process has been running too long (more than 6 hours)
            local start_time=$(date -d "$timestamp" +%s 2>/dev/null || echo "$current_time")
            local runtime=$((current_time - start_time))
            
            if [ $runtime -gt 21600 ]; then  # 6 hours in seconds
                log_message "Process $name (PID: $pid) has been running for $(($runtime / 3600)) hours, may be stuck" "WARNING"
                
                # For low priority processes that run too long, consider terminating
                if [ "$priority" != "high" ]; then
                    log_message "Terminating long-running process: $name (PID: $pid)" "WARNING"
                    kill -TERM "$pid" 2>/dev/null || true
                    zombie_count=$((zombie_count + 1))
                fi
            fi
        else
            # Process no longer exists, remove from tracking
            sed -i "/^$pid:/d" "$log_dir/active_processes.log"
        fi
    done < "$log_dir/active_processes.log"
    
    log_message "Process monitor: $running_count active processes, terminated $zombie_count zombie processes" "INFO"
}

# Display welcome banner
cat << "EOF" | tee -a "$log_file"
                                                                        
 ██████╗ ██████╗       ██████╗ ███████╗██╗   ██╗       ██████╗ ██████╗ 
 ██╔══██╗██╔══██╗      ██╔══██╗██╔════╝██║   ██║      ██╔═══██╗╚════██╗
 ██████╔╝██████╔╝█████╗██║  ██║█████╗  ██║   ██║█████╗██║   ██║ █████╔╝
 ██╔══██╗██╔══██╗╚════╝██║  ██║██╔══╝  ╚██╗ ██╔╝╚════╝██║   ██║██╔═══╝ 
 ██████╔╝██████╔╝      ██████╔╝███████╗ ╚████╔╝       ╚██████╔╝███████╗
 ╚═════╝ ╚═════╝       ╚═════╝ ╚══════╝  ╚═══╝         ╚═════╝ ╚══════╝
                                                                        
      Optimized reconnaissance automation framework by team7 v2.0       
                                                                        
EOF

# Confirmation that the script is running
log_message "BB-DEV-O2 runner is alive with PID $$, ctrl+c to exit" "SUCCESS"

# Check for configuration file
if [ ! -f "$config_file" ] && [ ! -f "$HOME/.bb-dev-o2_config" ]; then
    log_message "Configuration file not found. Creating default config at $config_file" "WARNING"
    
    cat > "$config_file" << EOL
#!/bin/sh

EMAIL_SENDER=""
EMAIL_RECIPIENT=""
EMAIL_SENDER_USERNAME=""
EMAIL_SENDER_PASSWORD=""
NIST_NVD_API_KEY=""

# Resource limits
MAX_PARALLEL_WORKFLOWS=3
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=90
EOL
    chmod 600 "$config_file"
    log_message "Please edit $config_file to add your email credentials and adjust resource limits" "WARNING"
fi

# Create templates directory if it doesn't exist
if [ ! -d "$templates_dir" ]; then
    mkdir -p "$templates_dir"
    
    # Create default email template
    cat > "$templates_dir/email_template.txt" << EOL
BB-DEV-O2 Notification
=======================
Timestamp: {{timestamp}}
Workflow: {{workflow}}
Target: {{target}}
Severity: {{severity}}
=======================

{{findings}}

=======================
This is an automated message from BB-DEV-O2.
EOL
    log_message "Created default email template at $templates_dir/email_template.txt" "INFO"
fi

# Cleanup old logs at startup
cleanup_old_logs

# Initialize child PIDs array
declare -a child_pids=()

# Track the last time we ran daily workflows
last_daily_run_date=""

# Enters the infinite loop
while true; do
    # Get current time
    current_mins=$(date -u +"%M")
    current_hours=$(date -u +"%H")
    current_date=$(date -u +"%Y-%m-%d")
    
    # Main scheduler - run at the top of every hour
    if [[ "$current_mins" == "00" ]]; then
        log_message "Hourly check - BB-DEV-O2 runner is alive with PID $$" "INFO"
        
        # Run daily workflows at 6:00 AM UTC if we haven't run them today
        if [[ "$current_hours" == "06" && "$current_date" != "$last_daily_run_date" ]]; then
            log_message "Running daily workflows" "INFO"
            last_daily_run_date="$current_date"
            
            # Process daily workflows
            if [ -d "$home_daily" ]; then
                # Count eligible workflows
                workflow_count=0
                for file in "$home_daily"/*; do
                    if [ -f "$file" ] && should_run_workflow "$file"; then
                        workflow_count=$((workflow_count + 1))
                    fi
                done
                
                log_message "Found $workflow_count daily workflows to run" "INFO"
                
                # Run workflows with appropriate priorities
                current_count=0
                for file in "$home_daily"/*; do
                    if [ -f "$file" ] && should_run_workflow "$file"; then
                        current_count=$((current_count + 1))
                        
                        # Set priority based on workflow number and position
                        priority="normal"
                        if [[ "$(basename "$file")" == *"1.sh" ]]; then
                            priority="high"  # workflow1.sh gets high priority
                        fi
                        
                        # Run the workflow
                        if run_workflow "$file" "$priority"; then
                            # Add a small delay between workflow launches to prevent resource spikes
                            sleep 5
                        fi
                        
                        log_message "Scheduled daily workflow $current_count/$workflow_count" "INFO"
                    fi
                done
            else
                log_message "Daily workflows directory not found: $home_daily" "WARNING"
                mkdir -p "$home_daily"
            fi
            
            # Run cleanup once per day
            cleanup_old_logs
        fi
        
        # Process hourly workflows
        if [ -d "$home_hourly" ]; then
            # Count eligible workflows
            workflow_count=0
            for file in "$home_hourly"/*; do
                if [ -f "$file" ] && should_run_workflow "$file"; then
                    workflow_count=$((workflow_count + 1))
                fi
            done
            
            if [ $workflow_count -gt 0 ]; then
                log_message "Found $workflow_count hourly workflows to run" "INFO"
                
                # Run workflows
                current_count=0
                for file in "$home_hourly"/*; do
                    if [ -f "$file" ] && should_run_workflow "$file"; then
                        current_count=$((current_count + 1))
                        run_workflow "$file" "normal"
                        
                        # Add a small delay between workflow launches
                        sleep 3
                        
                        log_message "Scheduled hourly workflow $current_count/$workflow_count" "INFO"
                    fi
                done
            fi
        else
            log_message "Hourly workflows directory not found: $home_hourly" "WARNING"
            mkdir -p "$home_hourly"
        fi
    fi
    
    # Check for zombie processes and clean them up every 30 minutes
    if [[ "$current_mins" == "30" ]]; then
        log_message "Performing process health check" "INFO"
        monitor_processes
    fi
    
    # Check system resources every 15 minutes
    if [[ "$current_mins" == "15" || "$current_mins" == "45" ]]; then
        check_system_resources
    fi

    # Sleep until next minute - more precise than sleeping for 60 seconds
    sleep $((60 - $(date +%S)))
done
