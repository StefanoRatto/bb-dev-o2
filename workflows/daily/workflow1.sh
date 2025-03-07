#!/bin/bash

# ============================================================================
# WORKFLOW1 - Subfinder -> httpx -> nuclei pipeline
# 
# This workflow discovers subdomains, checks for live HTTP services,
# and scans for vulnerabilities using nuclei.
# 
# Execution: Runs daily at 6:00 AM UTC via runner.sh
# Input: Files in inputs/ directory with names starting with "urls_"
# Output: Results stored in outputs/workflow1/YEAR/MONTH/TIMESTAMP/
# Notifications: Emails sent for medium, high, or critical findings
# ============================================================================

# Set strict error handling
set -o errexit  # Exit on error
set -o pipefail # Exit if any command in a pipe fails
set -o nounset  # Exit on undefined variables

# Define home folder
home=$(pwd)

# Define time stamp and directory structure
timestamp=$($home/now.sh)
current_year=$(date -u +"%Y")
current_month=$(date -u +"%m")

# Setup logging
log_file="$home/runner.log"
if [ ! -f "$log_file" ]; then
    touch "$log_file"
fi

# Function to log messages
log_message() {
    local message="[$($home/now.sh)] workflow1.sh: $1"
    echo "$message" | tee -a "$log_file"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required tools
required_tools=("subfinder" "httpx" "nuclei")
missing_tools=()

for tool in "${required_tools[@]}"; do
    if ! command_exists "$tool"; then
        missing_tools+=("$tool")
    fi
done

if [ ${#missing_tools[@]} -ne 0 ]; then
    log_message "ERROR: Missing required tools: ${missing_tools[*]}"
    log_message "Please install the missing tools and try again."
    exit 1
fi

# Update nuclei templates database with timeout and retry
log_message "Updating nuclei templates..."
nuclei_update_attempts=0
max_attempts=3

while [ $nuclei_update_attempts -lt $max_attempts ]; do
    if timeout 300 nuclei -ut -silent; then
        log_message "Nuclei templates updated successfully"
        break
    else
        nuclei_update_attempts=$((nuclei_update_attempts + 1))
        if [ $nuclei_update_attempts -lt $max_attempts ]; then
            log_message "Nuclei template update failed, retrying ($nuclei_update_attempts/$max_attempts)..."
            sleep 10
        else
            log_message "WARNING: Failed to update nuclei templates after $max_attempts attempts. Continuing with existing templates."
        fi
    fi
done

# Create output directory with proper structure
output_folder=$home/outputs/workflow1/$current_year/$current_month/$timestamp
if ! [ -d $output_folder ]; then
    mkdir -p $output_folder
    log_message "Created output directory: $output_folder"
fi

# Confirmation that the script started
log_message "Started at: $output_folder"

# Process input files
input_folder=$home/inputs
input_files_count=0
processed_files_count=0

# Function to process a single target file
process_target_file() {
    local file="$1"
    local filename="$(basename "$file")"
    
    log_message "Processing file: $filename"
    
    # Create results file if it doesn't exist
    if [ ! -f "$home/outputs/workflow1/results_$filename" ]; then
        touch "$home/outputs/workflow1/results_$filename"
        log_message "Created results file: results_$filename"
    fi

    # "Clean" the FQDNs from the scope files - using a temporary file to avoid sed issues
    cp "$file" "$output_folder/temp_input_$filename"
    sed -i 's/*.//g' "$output_folder/temp_input_$filename" 2>/dev/null
    sed -i 's/http:\/\///g' "$output_folder/temp_input_$filename" 2>/dev/null
    sed -i 's/https:\/\///g' "$output_folder/temp_input_$filename" 2>/dev/null
    
    # Count targets for logging
    target_count=$(wc -l < "$output_folder/temp_input_$filename")
    log_message "Found $target_count targets in $filename"
    
    # Skip empty files
    if [ "$target_count" -eq 0 ]; then
        log_message "WARNING: Empty input file, skipping: $filename"
        rm "$output_folder/temp_input_$filename"
        return
    fi
    
    # Create the subfinder output file with the content of the input file
    cp "$output_folder/temp_input_$filename" "$output_folder/subfinder_$filename"
    echo >> "$output_folder/subfinder_$filename"  # Add newline
    
    # Run subfinder with timeout and error handling
    log_message "Running subfinder on $filename..."
    if ! timeout 1800 subfinder -dL "$output_folder/temp_input_$filename" -silent 2>/dev/null >> "$output_folder/subfinder_$filename"; then
        log_message "WARNING: subfinder timed out or failed for $filename"
    fi
    
    # Count discovered subdomains
    subdomain_count=$(wc -l < "$output_folder/subfinder_$filename")
    log_message "Discovered $subdomain_count subdomains for $filename"
    
    # Run httpx with timeout and error handling
    log_message "Running httpx on discovered subdomains..."
    if ! timeout 1800 httpx -list "$output_folder/subfinder_$filename" \
        -silent -no-color -title -tech-detect -status-code -no-fallback -follow-redirects \
        -mc 200 -screenshot -srd "$output_folder" 2>/dev/null > "$output_folder/httpx_$filename"; then
        log_message "WARNING: httpx timed out or failed for $filename"
    fi
    
    # Count live URLs
    live_url_count=$(wc -l < "$output_folder/httpx_$filename")
    log_message "Found $live_url_count live URLs for $filename"
    
    # Prepare input for nuclei - extract URLs only
    awk '{print $1}' "$output_folder/httpx_$filename" 2>/dev/null > "$output_folder/temp_$filename"
    
    # Run nuclei with timeout and error handling
    log_message "Running nuclei vulnerability scan..."
    if ! timeout 3600 nuclei -l "$output_folder/temp_$filename" -s critical,high,medium,low \
        -silent -no-color 2>/dev/null > "$output_folder/nuclei_$filename"; then
        log_message "WARNING: nuclei timed out or failed for $filename"
    fi
    
    # Process nuclei findings
    if grep -qE "medium|high|critical" "$output_folder/nuclei_$filename"; then
        log_message "Found vulnerabilities in $filename, preparing notification..."
        
        # Extract medium, high, and critical findings
        grep -E "medium|high|critical" "$output_folder/nuclei_$filename" 2>/dev/null > "$output_folder/temp_$filename"
        
        # Clean up the findings for better readability
        sed -i 's/\t/ /g' "$output_folder/temp_$filename" 2>/dev/null  # Replace tabs with spaces
        sed -i 's/  */ /g' "$output_folder/temp_$filename" 2>/dev/null  # Remove duplicate spaces
        
        # Remove duplicate findings
        sort -u "$output_folder/temp_$filename" > "$output_folder/temp_sorted_$filename"
        mv "$output_folder/temp_sorted_$filename" "$output_folder/temp_$filename"
        
        # Check for new findings and prepare notification
        new_findings=false
        while IFS= read -r line; do
            if ! grep -Fxq "$line" "$home/outputs/workflow1/results_$filename"; then
                echo "$line" >> "$home/outputs/workflow1/results_$filename"
                echo "$line" >> "$output_folder/notify_$filename"
                new_findings=true
            fi
        done < "$output_folder/temp_$filename"
        
        # Send email notification if there are new findings
        if [ "$new_findings" = true ] && [ -f "$output_folder/notify_$filename" ]; then
            log_message "Sending email notification for new findings in $filename"
            sed -i 's/$/ /' "$output_folder/notify_$filename" 2>/dev/null
            
            # Add summary header to notification
            finding_count=$(wc -l < "$output_folder/notify_$filename")
            {
                echo "BB-DEV Vulnerability Notification"
                echo "=================================="
                echo "Timestamp: $timestamp"
                echo "Target file: $filename"
                echo "Total new findings: $finding_count"
                echo "=================================="
                echo ""
                cat "$output_folder/notify_$filename"
            } > "$output_folder/notify_formatted_$filename"
            
            # Send email with proper error handling
            if ! $home/email.sh "BB-DEV - workflow1/$timestamp/$filename - $finding_count new findings" \
                "$output_folder/notify_formatted_$filename" > /dev/null 2>&1; then
                log_message "WARNING: Failed to send email notification"
            else
                log_message "Email notification sent successfully"
            fi
        else
            log_message "No new findings to report for $filename"
        fi
    else
        log_message "No medium, high, or critical vulnerabilities found in $filename"
    fi
    
    # Clean up temporary files
    rm -f "$output_folder/temp_$filename" "$output_folder/temp_input_$filename"
    
    # Increment processed files counter
    processed_files_count=$((processed_files_count + 1))
    log_message "Completed processing $filename ($processed_files_count/$input_files_count)"
}

# Find and process all valid input files
for file in "$input_folder"/*; do
    if [ -f "$file" ]; then
        ext="${file##*.}"
        filename="$(basename "$file")"
        
        if [ "$ext" == "txt" ]; then
            if [[ "$filename" == urls* ]]; then
                input_files_count=$((input_files_count + 1))
            fi
        fi
    fi
done

log_message "Found $input_files_count input files to process"

# Process each input file
for file in "$input_folder"/*; do
    if [ -f "$file" ]; then
        ext="${file##*.}"
        filename="$(basename "$file")"
        
        if [ "$ext" == "txt" ]; then
            if [[ "$filename" == urls* ]]; then
                process_target_file "$file"
            elif [[ "$filename" == _urls* ]]; then
                log_message "Skipping disabled file: $filename"
            fi
        fi
    fi
done

# Confirmation that the script completed successfully
log_message "Completed at: $output_folder (Processed $processed_files_count/$input_files_count files)"

# Create a summary file
{
    echo "BB-DEV Workflow1 Summary"
    echo "========================"
    echo "Timestamp: $timestamp"
    echo "Files processed: $processed_files_count/$input_files_count"
    echo "Output directory: $output_folder"
    echo "========================"
} > "$output_folder/summary.txt"

exit 0
