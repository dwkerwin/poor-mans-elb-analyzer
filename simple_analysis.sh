#!/bin/bash

# Default log directory
LOG_DIR="${1:-elb-logs}"

echo "=== Simple ALB Log Analysis ==="
echo "Date: $(date)"
echo "Log directory: $LOG_DIR"
echo ""

# Check if log directory exists and has .log files
if [ ! -d "$LOG_DIR" ]; then
    echo "❌ Log directory '$LOG_DIR' not found."
    echo "Usage: $0 [log_directory]"
    exit 1
fi

LOG_FILES=$(find "$LOG_DIR" -name "*.log" -type f)
if [ -z "$LOG_FILES" ]; then
    echo "❌ No .log files found in '$LOG_DIR'"
    echo "Make sure you've unzipped the log files first."
    exit 1
fi

# Extract date range from logs
echo "📅 DATA RANGE ANALYSIS:"
echo "======================"
# Much more efficient: extract dates from filenames instead of processing all file contents
FIRST_DATE=$(find "$LOG_DIR" -name "*.log" -type f | sed 's/.*_\([0-9]\{8\}\)T[0-9]\{4\}Z_.*/\1/' | sort | head -1 | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3/')
LAST_DATE=$(find "$LOG_DIR" -name "*.log" -type f | sed 's/.*_\([0-9]\{8\}\)T[0-9]\{4\}Z_.*/\1/' | sort | tail -1 | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3/')
echo "First day in data: $FIRST_DATE"
echo "Last day in data: $LAST_DATE"
echo ""

echo "📊 SUMMARY:"
echo "Total requests: $(find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | wc -l)"
echo "Total log files: $(find "$LOG_DIR" -name "*.log" -type f | wc -l)"
echo ""

echo "🌐 TOP 10 CLIENT IPs:"
find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '{print $4}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -10
echo ""

echo "📈 STATUS CODES:"
find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '{print $9}' | sort | uniq -c | sort -nr
echo ""

echo "🔥 TOP 15 ENDPOINTS:"
find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '{print $13 " " $14 " " $15}' | sort | uniq -c | sort -nr | head -15
echo ""

echo "⚠️  ERROR REQUESTS (4xx/5xx):"
find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '$9 >= 400 {print $2, $4, $9, $13, $14, $15}' | head -10
echo ""

echo "🕒 REQUESTS BY HOUR:"
find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '{print $2}' | cut -dT -f2 | cut -d: -f1 | sort | uniq -c | sort -k2
echo ""

echo "Analysis complete! 🎉"
