# BB-DEV-O2

A robust and optimized reconnaissance automation framework for security testing.

## Overview

BB-DEV-O2 is an enhanced version of the BB-DEV framework designed to automate various security reconnaissance workflows. It runs different security scanning pipelines at scheduled intervals, processes the results, and sends notifications for significant findings. This O2 (Optimized v2) version includes significant performance, reliability, and security improvements.

## Installation

The easiest way to install BB-DEV-O2 and its dependencies is to use the provided installation script:

```bash
chmod +x install.sh
./install.sh
```

This script will:
1. Install all required dependencies
2. Create necessary directories
3. Set up configuration files
4. Make all scripts executable

### Manual Installation

If you prefer to install dependencies manually, you'll need:

- **Basic Tools**: git, curl, wget, python3, python3-pip, nmap, sendemail
- **Go-based Tools**: subfinder, httpx, nuclei, gau
- **Nmap Scripts**: nmap-vulscan, nmap-vulners

## Configuration

Edit the `.bb-dev-o2_config` file to configure your email settings:

```bash
EMAIL_SENDER="your-sender-email@example.com"
EMAIL_RECIPIENT="your-recipient-email@example.com"
EMAIL_SENDER_USERNAME="your-username"
EMAIL_SENDER_PASSWORD="your-password"
NIST_NVD_API_KEY="your-api-key"  # Optional, for NVD lookups
```

Make sure to set appropriate permissions:

```bash
chmod 600 .bb-dev-o2_config
```

## Directory Structure

- **workflows/**: Contains workflow scripts
  - **daily/**: Workflows that run daily
  - **hourly/**: Workflows that run hourly
- **inputs/**: Target URL files
- **outputs/**: Results from workflow runs
- **tools/**: Utility scripts and tools
- **logs/**: Log files from workflow runs

## Usage

### Adding Targets

Create text files in the `inputs/` directory with names starting with `urls_` (e.g., `urls_example.txt`). Each file should contain one target URL or domain per line.

Files with names starting with `_urls_` are ignored by the workflows.

### Running the Framework

Start the main runner script:

```bash
./runner.sh
```

This will continuously run in the background and launch workflows at scheduled times.

For best results, run it in a tmux or screen session:

```bash
tmux new -s bb-dev-o2
./runner.sh
# Press Ctrl+B, then D to detach
```

To reattach:

```bash
tmux attach -t bb-dev-o2
```

## Workflows

### workflow1.sh

**Pipeline**: subfinder -> httpx -> nuclei

This workflow discovers subdomains, checks for live HTTP services, and scans for vulnerabilities using nuclei. It runs daily at 6:00 AM UTC.

### workflow2.sh

**Pipeline**: subfinder -> nmap -> nmap-vulscan/nmap-vulners

This workflow discovers subdomains and scans for vulnerabilities using nmap scripts. It runs daily at 6:00 AM UTC.

### workflow3.sh

**Pipeline**: subfinder -> httpx -> gau

This workflow discovers subdomains, checks for live HTTP services, and collects URLs using gau. It runs daily at 6:00 AM UTC.

### workflow4.sh

**Pipeline**: subfinder -> httpx -> checksum

This workflow monitors websites for changes by comparing content checksums. It runs daily at 6:00 AM UTC.

## Utility Scripts

### runner.sh

The main orchestrator that runs workflows at different cadences (hourly/daily).

### now.sh

Utility script that prints the current timestamp in a consistent format.

### email.sh

Utility script for sending email notifications.

### install.sh

Script to install all dependencies and set up the framework.

## Performance and Reliability Improvements

The O2 version includes several enhanced features to ensure reliability and performance:

- **Advanced Error Handling**: Comprehensive error handling with detailed error messages and recovery mechanisms
- **Smart Timeouts**: Adaptive timeouts based on workload size and system resources
- **Multi-level Retry Logic**: Exponential backoff and intelligent retry strategies for critical operations
- **Resource Management**: Dynamic resource allocation and throttling to prevent system overload
- **Comprehensive Logging**: Structured logging with severity levels and rotation
- **Process Isolation**: Enhanced process isolation with resource limits
- **Parallel Processing**: Optimized parallel execution where appropriate
- **Memory Optimization**: Reduced memory footprint for long-running processes
- **Security Hardening**: Improved input validation and sanitization
- **Graceful Degradation**: Ability to continue operation with reduced functionality when resources are constrained

## Security Enhancements

BB-DEV-O2 includes several security improvements:

- **Input Validation**: Thorough validation of all user inputs
- **Secure Configuration**: Enhanced protection of sensitive configuration data
- **Least Privilege**: Operations run with minimal required permissions
- **Secure Communication**: Enforced TLS for all external communications
- **Dependency Security**: Regular updates of dependencies to patch vulnerabilities
- **Audit Logging**: Comprehensive logging of security-relevant events

## Customization

You can customize the framework by:

1. Adding new workflows in the `workflows/daily/` or `workflows/hourly/` directories
2. Modifying existing workflows to use different tools or parameters
3. Adjusting the scheduling in `runner.sh`
4. Creating custom notification templates in the `templates/` directory

## Troubleshooting

Check the log files in the `logs/` directory for detailed information about workflow runs.

Common issues:
- Missing dependencies: Run `./install.sh` to install all required dependencies
- Email configuration: Ensure your email credentials are correct in `.bb-dev-o2_config`
- Permissions: Make sure all scripts are executable (`chmod +x *.sh`)
- Resource constraints: Adjust the resource limits in the configuration file

## Licensing

The tool is licensed under the [GNU General Public License](https://www.gnu.org/licenses/gpl-3.0.en.html).

## Legal disclaimer

Usage of this tool to interact with targets without prior mutual consent is illegal. It's the end user's responsibility to obey all applicable local, state and federal laws. Developers assume no liability and are not responsible for any misuse or damage caused by this program. Only use for educational purposes.
