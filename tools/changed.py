#!/usr/bin/env python3

"""
BB-DEV-O2 Website Change Detector

This script monitors websites for changes by comparing content hashes.
When changes are detected, it sends email notifications.

Author: raste
Version: 2.0.0
Organization: team7
"""

import argparse
import hashlib
import os
import time
import smtplib
import logging
import sys
import signal
import json
import re
import threading
import queue
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError
import socket
import ssl
import random
from pathlib import Path

# Set up logging with configurable level
log_level = os.environ.get("BB_DEV_O2_LOG_LEVEL", "INFO").upper()
numeric_level = getattr(logging, log_level, logging.INFO)

# Create logs directory if it doesn't exist
log_dir = Path(os.getcwd()) / "logs"
log_dir.mkdir(exist_ok=True)

# Configure logging
logging.basicConfig(
    level=numeric_level,
    format='%(asctime)s - %(levelname)s - [PID:%(process)d] - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S',
    handlers=[
        logging.FileHandler(log_dir / "changed.log"),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Global flags
running = True
config = {}

def load_config():
    """Load configuration from .bb-dev-o2_config file."""
    config_paths = [
        os.path.expanduser("~/.bb-dev-o2_config"),
        os.path.join(os.getcwd(), ".bb-dev-o2_config")
    ]
    
    for config_path in config_paths:
        if os.path.exists(config_path):
            logger.info(f"Loading configuration from {config_path}")
            
            # Parse the config file
            with open(config_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        key, value = line.split('=', 1)
                        # Remove quotes if present
                        value = value.strip().strip('"\'')
                        config[key.strip()] = value
            
            return True
    
    logger.error("No configuration file found")
    return False

def setup_signal_handlers():
    """Set up signal handlers for graceful shutdown."""
    def signal_handler(sig, frame):
        global running
        logger.info(f"Received signal {sig}, shutting down gracefully...")
        running = False
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

def fetch_url_content(url, timeout=30, max_retries=3, user_agent=None):
    """
    Fetch content from a URL with retry logic.
    
    Args:
        url: The URL to fetch
        timeout: Connection timeout in seconds
        max_retries: Maximum number of retry attempts
        user_agent: Custom user agent string
        
    Returns:
        Content of the URL or None if failed
    """
    # List of user agents to rotate through
    user_agents = [
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.1 Safari/605.1.15',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:89.0) Gecko/20100101 Firefox/89.0',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
    ]
    
    # Use provided user agent or pick a random one
    if not user_agent:
        user_agent = random.choice(user_agents)
    
    headers = {
        'User-Agent': user_agent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
        'Cache-Control': 'max-age=0'
    }
    
    for attempt in range(max_retries):
        try:
            req = Request(url, headers=headers)
            with urlopen(req, timeout=timeout) as response:
                return response.read()
        except HTTPError as e:
            logger.error(f"HTTP Error for {url}: {e.code} - {e.reason}")
            if attempt == max_retries - 1:
                return None
        except URLError as e:
            logger.error(f"URL Error for {url}: {e.reason}")
            if attempt == max_retries - 1:
                return None
        except (socket.timeout, ssl.SSLError, ConnectionResetError) as e:
            logger.error(f"Connection error for {url}: {str(e)}")
            if attempt == max_retries - 1:
                return None
        except Exception as e:
            logger.error(f"Unexpected error for {url}: {str(e)}")
            if attempt == max_retries - 1:
                return None
        
        # Exponential backoff with jitter
        wait_time = (2 ** attempt) + random.uniform(0, 1)
        logger.info(f"Retrying {url} in {wait_time:.2f} seconds... (Attempt {attempt+1}/{max_retries})")
        time.sleep(wait_time)
    
    return None

def calculate_hash(content):
    """Calculate SHA-256 hash of content."""
    return hashlib.sha256(content).hexdigest()

def send_email_notification(target, old_hash, new_hash):
    """
    Send email notification about website changes.
    
    Args:
        target: The URL that changed
        old_hash: Previous content hash
        new_hash: New content hash
    
    Returns:
        Boolean indicating success or failure
    """
    try:
        # Get email configuration from loaded config
        sender_email = config.get('EMAIL_SENDER', '')
        receiver_email = config.get('EMAIL_RECIPIENT', '')
        username = config.get('EMAIL_SENDER_USERNAME', '')
        password = config.get('EMAIL_SENDER_PASSWORD', '')
        
        if not all([sender_email, receiver_email, username, password]):
            logger.error("Email configuration is incomplete")
            return False
        
        timestamp = datetime.now().astimezone().isoformat()
        subject = f"[BB-DEV-O2] Website Changed: {target}"
        
        # Create a multipart message
        message = MIMEMultipart()
        message['From'] = sender_email
        message['To'] = receiver_email
        message['Subject'] = subject
        
        # Create HTML version of the message
        html_content = f"""
        <html>
        <head>
            <style>
                body {{ font-family: Arial, sans-serif; }}
                .header {{ background-color: #4CAF50; color: white; padding: 10px; }}
                .content {{ padding: 15px; }}
                .footer {{ background-color: #f1f1f1; padding: 10px; font-size: 0.8em; }}
                .hash {{ font-family: monospace; background-color: #f8f8f8; padding: 5px; }}
            </style>
        </head>
        <body>
            <div class="header">
                <h2>BB-DEV-O2 Website Change Notification</h2>
            </div>
            <div class="content">
                <p><strong>Timestamp:</strong> {timestamp}</p>
                <p><strong>URL:</strong> <a href="{target}">{target}</a></p>
                <p><strong>Status:</strong> CHANGED</p>
                <p><strong>Previous Hash:</strong> <span class="hash">{old_hash[:16]}...</span></p>
                <p><strong>New Hash:</strong> <span class="hash">{new_hash[:16]}...</span></p>
                <p>Please check the website for updates.</p>
            </div>
            <div class="footer">
                This is an automated message from BB-DEV-O2 Website Change Detector.
            </div>
        </body>
        </html>
        """
        
        # Create plain text version of the message
        text_content = f"""
BB-DEV-O2 Website Change Notification
=====================================
Timestamp: {timestamp}
URL: {target}
Status: CHANGED

Previous Hash: {old_hash[:16]}...
New Hash: {new_hash[:16]}...

Please check the website for updates.
=====================================
This is an automated message from BB-DEV-O2.
        """
        
        # Attach parts
        part1 = MIMEText(text_content, 'plain')
        part2 = MIMEText(html_content, 'html')
        message.attach(part1)
        message.attach(part2)
        
        # Connect to server and send email
        max_attempts = 3
        for attempt in range(max_attempts):
            try:
                server = smtplib.SMTP('smtp.gmail.com', 587)
                server.starttls()
                server.login(username, password)
                server.sendmail(sender_email, receiver_email, message.as_string())
                server.quit()
                logger.info(f"Email notification sent for {target}")
                return True
            except Exception as e:
                logger.error(f"Attempt {attempt+1}/{max_attempts} failed to send email: {str(e)}")
                if attempt < max_attempts - 1:
                    time.sleep(5)
        
        logger.error(f"Failed to send email notification for {target} after {max_attempts} attempts")
        return False
    except Exception as e:
        logger.error(f"Failed to send email notification for {target}: {str(e)}")
        return False

def load_targets(targets_file):
    """
    Load target URLs from file.
    
    Args:
        targets_file: Path to file containing target URLs
        
    Returns:
        List of target URLs
    """
    if not os.path.exists(targets_file):
        logger.error(f"Targets file not found: {targets_file}")
        sys.exit(1)
        
    try:
        with open(targets_file) as f:
            targets = []
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    # Ensure URL has a scheme
                    if not re.match(r'^https?://', line):
                        line = 'http://' + line
                    targets.append(line)
            return targets
    except Exception as e:
        logger.error(f"Error reading targets file: {str(e)}")
        sys.exit(1)

def save_state(data, state_file):
    """Save the current state to a file."""
    try:
        with open(state_file, 'w') as f:
            json.dump(data, f)
        logger.debug(f"State saved to {state_file}")
    except Exception as e:
        logger.error(f"Failed to save state: {str(e)}")

def load_state(state_file):
    """Load the previous state from a file."""
    if not os.path.exists(state_file):
        logger.info(f"No previous state file found at {state_file}")
        return {}
    
    try:
        with open(state_file, 'r') as f:
            data = json.load(f)
        logger.info(f"Loaded previous state from {state_file} with {len(data)} entries")
        return data
    except Exception as e:
        logger.error(f"Failed to load state: {str(e)}")
        return {}

def worker(work_queue, result_queue, user_agent):
    """Worker function for thread pool."""
    while running:
        try:
            # Get a task from the queue with a timeout
            target = work_queue.get(timeout=1)
            
            # Process the target
            logger.debug(f"Worker processing {target}")
            content = fetch_url_content(target, user_agent=user_agent)
            
            if content:
                new_hash = calculate_hash(content)
                result_queue.put((target, new_hash))
            else:
                result_queue.put((target, None))
            
            # Mark the task as done
            work_queue.task_done()
        except queue.Empty:
            # No more tasks in the queue
            pass
        except Exception as e:
            logger.error(f"Worker error: {str(e)}")
            try:
                work_queue.task_done()
            except:
                pass

def main(args):
    """Main function to monitor websites for changes."""
    global running
    
    # Load configuration
    if not load_config():
        logger.warning("Using default configuration")
    
    # Set up signal handlers for graceful shutdown
    setup_signal_handlers()
    
    logger.info(f"Starting BB-DEV-O2 website change monitor with PID {os.getpid()}")
    
    # Load targets
    targets = load_targets(args.targets_file)
    logger.info(f"Loaded {len(targets)} targets from {args.targets_file}")
    
    # State file for persistence
    state_file = os.path.join(os.path.dirname(args.targets_file), 
                             f".{os.path.basename(args.targets_file)}.state.json")
    
    # Load previous state
    data = load_state(state_file)
    
    # Initialize data for new targets
    for target in targets:
        if target not in data:
            data[target] = {
                'hash': None,
                'last_checked': None,
                'last_changed': None,
                'check_count': 0,
                'change_count': 0,
                'error_count': 0
            }
    
    # Main monitoring loop
    check_interval = args.interval
    
    while running:
        try:
            start_time = time.time()
            logger.info(f"Starting check cycle for {len(targets)} targets")
            
            # Create thread-safe queues
            work_queue = queue.Queue()
            result_queue = queue.Queue()
            
            # Add all targets to the work queue
            for target in targets:
                work_queue.put(target)
            
            # Create worker threads
            threads = []
            num_threads = min(args.threads, len(targets))
            
            for i in range(num_threads):
                # Each thread gets a different user agent
                user_agent = f"BB-DEV-O2/2.0.0 Monitor Thread-{i+1}"
                t = threading.Thread(target=worker, args=(work_queue, result_queue, user_agent))
                t.daemon = True
                t.start()
                threads.append(t)
            
            # Wait for all tasks to be processed
            work_queue.join()
            
            # Process results
            changes_detected = 0
            errors = 0
            
            while not result_queue.empty():
                target, new_hash = result_queue.get()
                
                # Update check count and last checked time
                data[target]['check_count'] += 1
                data[target]['last_checked'] = datetime.now().isoformat()
                
                if new_hash is None:
                    # Error fetching the target
                    data[target]['error_count'] += 1
                    errors += 1
                    continue
                
                current_hash = data[target]['hash']
                
                if current_hash is None:
                    # First time checking this target
                    logger.info(f"Initial hash for {target}: {new_hash[:16]}...")
                    data[target]['hash'] = new_hash
                    data[target]['last_changed'] = datetime.now().isoformat()
                elif new_hash != current_hash:
                    # Hash has changed
                    logger.info(f"{target} - CHANGED! Old hash: {current_hash[:16]}..., New hash: {new_hash[:16]}...")
                    
                    # Send notification
                    if send_email_notification(target, current_hash, new_hash):
                        # Update state only if notification was sent successfully
                        data[target]['hash'] = new_hash
                        data[target]['last_changed'] = datetime.now().isoformat()
                        data[target]['change_count'] += 1
                        changes_detected += 1
                else:
                    # No change
                    logger.info(f"{target} - No changes detected")
            
            # Save state after each check cycle
            save_state(data, state_file)
            
            # Calculate time taken and sleep until next interval
            elapsed_time = time.time() - start_time
            logger.info(f"Check cycle completed in {elapsed_time:.2f} seconds. "
                       f"Changes: {changes_detected}, Errors: {errors}")
            
            # Calculate sleep time, ensuring we don't sleep negative time
            sleep_time = max(1, check_interval - elapsed_time)
            
            logger.info(f"Sleeping for {sleep_time:.2f} seconds before next check...")
            
            # Sleep in smaller increments to allow for faster shutdown
            sleep_increment = 10
            for _ in range(int(sleep_time / sleep_increment)):
                if not running:
                    break
                time.sleep(sleep_increment)
            
            # Sleep any remaining time
            if running and sleep_time % sleep_increment > 0:
                time.sleep(sleep_time % sleep_increment)
                
        except Exception as e:
            logger.error(f"Unexpected error in main loop: {str(e)}")
            # Sleep a bit to avoid tight error loops
            time.sleep(30)
    
    logger.info("Shutting down gracefully...")
    
    # Save state one last time before exiting
    save_state(data, state_file)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="BB-DEV-O2 Website Change Monitor")
    
    parser.add_argument("-t", "--targets", dest="targets_file", required=True,
                        help="File containing list of URLs to monitor")
    
    parser.add_argument("-i", "--interval", dest="interval", type=int, default=300,
                        help="Check interval in seconds (default: 300)")
    
    parser.add_argument("--threads", dest="threads", type=int, default=5,
                        help="Number of worker threads (default: 5)")
    
    parser.add_argument("-v", "--version", action="version",
                        version="BB-DEV-O2 Website Change Monitor v2.0.0")
    
    parser.add_argument("--debug", action="store_true",
                        help="Enable debug logging")
    
    args = parser.parse_args()
    
    # Set debug level if requested
    if args.debug:
        logger.setLevel(logging.DEBUG)
        logger.debug("Debug logging enabled")
    
    try:
        main(args)
    except Exception as e:
        logger.critical(f"Fatal error: {str(e)}")
        sys.exit(1)
