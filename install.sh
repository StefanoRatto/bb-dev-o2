#!/bin/bash

# ============================================================================
# BB-DEV-O2 INSTALLER - Sets up dependencies for the BB-DEV-O2 framework
# 
# This script installs all required dependencies for the BB-DEV-O2 framework.
# It checks for existing tools and installs missing ones.
#
# Version: 2.0.0
# ============================================================================

set -e  # Exit on error

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Define home folder and paths
home=$(pwd)
log_dir="$home/logs"
config_file="$home/.bb-dev-o2_config"
templates_dir="$home/templates"

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install a package using apt
install_package() {
    local package=$1
    print_message "$YELLOW" "Installing $package..."
    sudo apt-get install -y "$package"
    print_message "$GREEN" "$package installed successfully."
}

# Function to install Go tools
install_go_tool() {
    local tool=$1
    local repo=$2
    print_message "$YELLOW" "Installing $tool..."
    go install "$repo"@latest
    print_message "$GREEN" "$tool installed successfully."
}

# Function to check system compatibility
check_system_compatibility() {
    print_message "$BLUE" "Checking system compatibility..."
    
    # Check OS
    if [[ "$(uname)" != "Linux" ]]; then
        print_message "$YELLOW" "Warning: This installer is designed for Linux. Some features may not work on your OS: $(uname)"
    fi
    
    # Check for sudo access
    if ! command_exists sudo; then
        print_message "$RED" "Error: 'sudo' is required for installation but not found."
        exit 1
    fi
    
    # Check for basic required commands
    for cmd in curl wget git; do
        if ! command_exists "$cmd"; then
            print_message "$YELLOW" "Warning: '$cmd' is not installed. Will attempt to install it."
        fi
    done
    
    # Check disk space
    local free_space=$(df -k . | awk 'NR==2 {print $4}')
    if [ "$free_space" -lt 1000000 ]; then  # Less than 1GB
        print_message "$YELLOW" "Warning: Low disk space detected. At least 1GB of free space is recommended."
    fi
    
    print_message "$GREEN" "System compatibility check completed."
}

# Function to create backup of existing configuration
create_backup() {
    if [ -f "$config_file" ]; then
        local backup_file="$config_file.bak.$(date +%s)"
        print_message "$YELLOW" "Creating backup of existing configuration: $backup_file"
        cp "$config_file" "$backup_file"
    fi
}

# Welcome message
cat << "EOF"
============================================================
 ██████╗ ██████╗       ██████╗ ███████╗██╗   ██╗       ██████╗ ██████╗ 
 ██╔══██╗██╔══██╗      ██╔══██╗██╔════╝██║   ██║      ██╔═══██╗╚════██╗
 ██████╔╝██████╔╝█████╗██║  ██║█████╗  ██║   ██║█████╗██║   ██║ █████╔╝
 ██╔══██╗██╔══██╗╚════╝██║  ██║██╔══╝  ╚██╗ ██╔╝╚════╝██║   ██║██╔═══╝ 
 ██████╔╝██████╔╝      ██████╔╝███████╗ ╚████╔╝       ╚██████╔╝███████╗
 ╚═════╝ ╚═════╝       ╚═════╝ ╚══════╝  ╚═══╝         ╚═════╝ ╚══════╝
                                                                        
      Optimized reconnaissance automation framework by team7 v2.0       
============================================================
This script will install all required dependencies for the
BB-DEV-O2 reconnaissance automation framework.
============================================================
EOF

# Check system compatibility
check_system_compatibility

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_message "$YELLOW" "Note: Some installations may require sudo privileges."
fi

# Create backup of existing configuration
create_backup

# Create necessary directories
print_message "$YELLOW" "Creating necessary directories..."
mkdir -p outputs/workflow1
mkdir -p outputs/workflow2
mkdir -p outputs/workflow3
mkdir -p outputs/workflow4
mkdir -p "$log_dir"
mkdir -p workflows/hourly
mkdir -p "$templates_dir"
print_message "$GREEN" "Directories created successfully."

# Update package lists
print_message "$YELLOW" "Updating package lists..."
sudo apt-get update
print_message "$GREEN" "Package lists updated."

# Install basic dependencies
print_message "$YELLOW" "Installing basic dependencies..."
packages=("git" "curl" "wget" "python3" "python3-pip" "nmap" "sendemail" "bc" "gzip" "jq")
for package in "${packages[@]}"; do
    if ! command_exists "$package"; then
        install_package "$package"
    else
        print_message "$GREEN" "$package is already installed."
    fi
done

# Check and install Go if needed
if ! command_exists "go"; then
    print_message "$YELLOW" "Installing Go..."
    wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
    sudo tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz
    echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bashrc
    source ~/.bashrc
    rm go1.21.0.linux-amd64.tar.gz
    print_message "$GREEN" "Go installed successfully."
else
    print_message "$GREEN" "Go is already installed."
fi

# Install Go-based tools
go_tools=(
    "subfinder:github.com/projectdiscovery/subfinder/v2/cmd/subfinder"
    "httpx:github.com/projectdiscovery/httpx/cmd/httpx"
    "nuclei:github.com/projectdiscovery/nuclei/v2/cmd/nuclei"
    "gau:github.com/lc/gau/v2/cmd/gau"
)

for tool_info in "${go_tools[@]}"; do
    tool_name="${tool_info%%:*}"
    tool_repo="${tool_info#*:}"
    
    if ! command_exists "$tool_name"; then
        install_go_tool "$tool_name" "$tool_repo"
    else
        print_message "$GREEN" "$tool_name is already installed."
    fi
done

# Install nmap scripts
if [ ! -d "/usr/share/nmap/scripts/vulscan" ]; then
    print_message "$YELLOW" "Installing nmap-vulscan..."
    sudo git clone https://github.com/scipag/vulscan /usr/share/nmap/scripts/vulscan
    print_message "$GREEN" "nmap-vulscan installed successfully."
else
    print_message "$GREEN" "nmap-vulscan is already installed."
fi

if [ ! -f "/usr/share/nmap/scripts/vulners.nse" ]; then
    print_message "$YELLOW" "Installing nmap-vulners..."
    sudo wget -O /usr/share/nmap/scripts/vulners.nse https://raw.githubusercontent.com/vulnersCom/nmap-vulners/master/vulners.nse
    sudo nmap --script-updatedb
    print_message "$GREEN" "nmap-vulners installed successfully."
else
    print_message "$GREEN" "nmap-vulners is already installed."
fi

# Install Python dependencies
print_message "$YELLOW" "Installing Python dependencies..."
pip3 install requests urllib3 argparse colorama tqdm

# Create default config file if it doesn't exist
if [ ! -f "$config_file" ]; then
    print_message "$YELLOW" "Creating default configuration file..."
    cat > "$config_file" << EOL
#!/bin/sh

# Email configuration
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

# Notification settings
NOTIFY_ON_START=true
NOTIFY_ON_COMPLETION=true
NOTIFY_ON_ERROR=true
EOL
    chmod 600 "$config_file"
    print_message "$GREEN" "Default configuration file created."
    print_message "$YELLOW" "Please edit $config_file to add your email credentials."
else
    print_message "$GREEN" "Configuration file already exists."
fi

# Create default email template
if [ ! -f "$templates_dir/email_template.txt" ]; then
    print_message "$YELLOW" "Creating default email template..."
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
    print_message "$GREEN" "Default email template created."
fi

# Make scripts executable
print_message "$YELLOW" "Making scripts executable..."
chmod +x *.sh
chmod +x workflows/daily/*.sh 2>/dev/null || true
chmod +x workflows/hourly/*.sh 2>/dev/null || true
chmod +x tools/*.py 2>/dev/null || true
print_message "$GREEN" "Scripts are now executable."

# Update any existing .bb-dev_config to .bb-dev-o2_config
if [ -f "$home/.bb-dev_config" ] && [ ! -f "$config_file" ]; then
    print_message "$YELLOW" "Migrating existing .bb-dev_config to .bb-dev-o2_config..."
    cp "$home/.bb-dev_config" "$config_file"
    chmod 600 "$config_file"
    print_message "$GREEN" "Configuration migrated successfully."
fi

# Create a simple test target file if none exist
if [ ! -f "$home/inputs/urls_test.txt" ]; then
    print_message "$YELLOW" "Creating a test target file..."
    mkdir -p "$home/inputs"
    echo "example.com" > "$home/inputs/urls_test.txt"
    print_message "$GREEN" "Test target file created: inputs/urls_test.txt"
fi

# Final message
print_message "$GREEN" "============================================================"
print_message "$GREEN" "BB-DEV-O2 framework dependencies installed successfully!"
print_message "$GREEN" "============================================================"
print_message "$YELLOW" "Next steps:"
echo "1. Edit $config_file to add your email credentials"
echo "2. Add target URLs to the inputs/ directory"
echo "3. Run ./runner.sh to start the framework"
print_message "$GREEN" "============================================================"

exit 0 