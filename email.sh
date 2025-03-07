#!/bin/bash

# ============================================================================
# BB-DEV-O2 EMAIL UTILITY - Sends email notifications from BB-DEV-O2
# 
# This script sends email notifications with configurable subject and body.
# It reads email configuration from .bb-dev-o2_config file and supports
# template-based emails.
# 
# Usage: ./email.sh "Subject" "Path to message body file" [template_name]
# Version: 2.0.0
# ============================================================================

# Set strict error handling
set -o errexit  # Exit on error
set -o pipefail # Exit if any command in a pipe fails
set -o nounset  # Exit on undefined variables

# Define home folder and paths
home=$(pwd)
log_dir="$home/logs"
templates_dir="$home/templates"

# Create logs directory if it doesn't exist
mkdir -p "$log_dir"
mkdir -p "$templates_dir"

# Function to log messages with severity
log_message() {
    local message="$1"
    local severity="${2:-INFO}"
    local timestamp=$(date -u +"%y-%m-%d_%H_%M_%S_UTC")
    local log_entry="[$timestamp] [email.sh] [$severity] $message"
    
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
    
    echo "$log_entry" >> "$log_dir/email.log"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to sanitize input
sanitize_input() {
    local input="$1"
    # Remove any potentially dangerous characters
    echo "$input" | sed 's/[;<>\`\|]//g'
}

# Function to apply template
apply_template() {
    local template_file="$1"
    local body_file="$2"
    local output_file="$3"
    
    if [ ! -f "$template_file" ]; then
        log_message "Template file not found: $template_file" "ERROR"
        return 1
    fi
    
    if [ ! -f "$body_file" ]; then
        log_message "Body file not found: $body_file" "ERROR"
        return 1
    }
    
    # Create a temporary file for the output
    local temp_file=$(mktemp)
    
    # Read the template and replace placeholders
    cat "$template_file" > "$temp_file"
    
    # Replace {{findings}} with the content of the body file
    sed -i -e "/{{findings}}/r $body_file" -e '/{{findings}}/d' "$temp_file"
    
    # Replace other common placeholders
    sed -i "s/{{timestamp}}/$(date -u +"%Y-%m-%d %H:%M:%S UTC")/g" "$temp_file"
    sed -i "s/{{workflow}}/$(basename "$body_file" | cut -d '_' -f 1)/g" "$temp_file"
    sed -i "s/{{target}}/$(basename "$body_file" | cut -d '_' -f 2- | sed 's/\.txt$//')/g" "$temp_file"
    
    # Move the temp file to the output file
    mv "$temp_file" "$output_file"
    
    return 0
}

# Check for required parameters
if [ $# -lt 2 ]; then
    log_message "Missing required parameters" "ERROR"
    echo "Usage: $0 \"Subject\" \"Path to message body file\" [template_name]"
    exit 1
fi

# Assign parameters to variables
email_subject=$(sanitize_input "$1")
email_body_file=$(sanitize_input "$2")
template_name="${3:-}"

# Check if the body file exists
if [ ! -f "$email_body_file" ]; then
    log_message "Message body file not found: $email_body_file" "ERROR"
    exit 1
fi

# Check for required tools
if ! command_exists sendemail; then
    log_message "Required tool 'sendemail' is not installed" "ERROR"
    exit 1
fi

# Load configuration from .bb-dev-o2_config
config_file="$HOME/.bb-dev-o2_config"
if [ ! -f "$config_file" ]; then
    config_file="$home/.bb-dev-o2_config"
fi

if [ ! -f "$config_file" ]; then
    log_message "Configuration file not found: $config_file" "ERROR"
    exit 1
fi

# Source the configuration file
source "$config_file"

# Validate configuration
if [ -z "${EMAIL_SENDER:-}" ] || [ -z "${EMAIL_RECIPIENT:-}" ] || 
   [ -z "${EMAIL_SENDER_USERNAME:-}" ] || [ -z "${EMAIL_SENDER_PASSWORD:-}" ]; then
    log_message "Missing email configuration in $config_file" "ERROR"
    log_message "Please ensure EMAIL_SENDER, EMAIL_RECIPIENT, EMAIL_SENDER_USERNAME, and EMAIL_SENDER_PASSWORD are set" "ERROR"
    exit 1
fi

# Apply template if specified
if [ -n "$template_name" ]; then
    template_file="$templates_dir/${template_name}.txt"
    
    if [ ! -f "$template_file" ]; then
        # Try default template if specific template not found
        template_file="$templates_dir/email_template.txt"
    fi
    
    if [ -f "$template_file" ]; then
        log_message "Applying template: $template_file" "INFO"
        
        # Create a temporary file for the templated content
        templated_body_file=$(mktemp)
        
        if apply_template "$template_file" "$email_body_file" "$templated_body_file"; then
            email_body_file="$templated_body_file"
            log_message "Template applied successfully" "SUCCESS"
        else
            log_message "Failed to apply template, using original body" "WARNING"
        fi
    else
        log_message "No template found, using original body" "WARNING"
    fi
fi

# Log the email attempt
log_message "Sending email: \"$email_subject\" to $EMAIL_RECIPIENT" "INFO"

# Attempt to send the email with retry logic and exponential backoff
max_attempts=5
attempt=1
success=false
backoff_time=10

while [ $attempt -le $max_attempts ] && [ "$success" = false ]; do
    if timeout 60 sendemail -f "$EMAIL_SENDER" \
                -t "$EMAIL_RECIPIENT" \
                -u "$email_subject" \
                -o message-file="$email_body_file" \
                -s "smtp.gmail.com:587" \
                -xu "$EMAIL_SENDER_USERNAME" \
                -xp "$EMAIL_SENDER_PASSWORD" \
                -o tls=yes; then
        log_message "Email sent successfully" "SUCCESS"
        success=true
    else
        log_message "Attempt $attempt/$max_attempts failed to send email" "WARNING"
        if [ $attempt -lt $max_attempts ]; then
            log_message "Retrying in $backoff_time seconds..." "INFO"
            sleep $backoff_time
            # Exponential backoff with jitter
            backoff_time=$(( backoff_time * 2 + (RANDOM % 5) ))
        fi
        attempt=$((attempt + 1))
    fi
done

# Clean up temporary files
if [ -n "${templated_body_file:-}" ] && [ -f "$templated_body_file" ]; then
    rm -f "$templated_body_file"
fi

if [ "$success" = false ]; then
    log_message "Failed to send email after $max_attempts attempts" "ERROR"
    exit 1
fi

log_message "Email operation completed successfully" "SUCCESS"
exit 0
