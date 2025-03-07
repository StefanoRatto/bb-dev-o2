#!/bin/bash

# ============================================================================
# BB-DEV-O2 NOW UTILITY - Provides consistent timestamp format for BB-DEV-O2
# 
# This script outputs the current UTC timestamp in a consistent format
# that is used throughout the BB-DEV-O2 framework for logging and directories.
# 
# Format: YY-MM-DD_HH_MM_SS_UTC
# Usage: ./now.sh [format]
# 
# Optional format parameter:
#   default: YY-MM-DD_HH_MM_SS_UTC
#   iso:     ISO 8601 format (YYYY-MM-DDTHH:MM:SSZ)
#   log:     YYYY-MM-DD HH:MM:SS
#   unix:    Unix timestamp (seconds since epoch)
#
# Version: 2.0.0
# ============================================================================

# Set strict error handling
set -o errexit  # Exit on error
set -o pipefail # Exit if any command in a pipe fails
set -o nounset  # Exit on undefined variables

# Process command line arguments
format="${1:-default}"

# Output the timestamp in the requested format
case "$format" in
    iso)
        date -u +"%Y-%m-%dT%H:%M:%SZ"
        ;;
    log)
        date -u +"%Y-%m-%d %H:%M:%S"
        ;;
    unix)
        date -u +"%s"
        ;;
    *)
        # Default format
        date -u +"%y-%m-%d_%H_%M_%S_UTC"
        ;;
esac

exit 0