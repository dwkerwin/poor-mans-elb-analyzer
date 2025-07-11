#!/bin/bash

# Convert ALB logs to GoAccess format
# Usage: ./convert_to_goaccess.sh [log_directory] [output_file]

# Default values
LOG_DIR="${1:-elb-logs}"
OUTPUT_FILE="${2:-elb_converted.log}"

# Check if log directory exists
if [ ! -d "$LOG_DIR" ]; then
    echo "Error: Log directory '$LOG_DIR' not found."
    echo "Usage: $0 [log_directory] [output_file]"
    exit 1
fi

# Find all .log files in the directory and subdirectories
LOG_FILES=$(find "$LOG_DIR" -name "*.log" -type f)

if [ -z "$LOG_FILES" ]; then
    echo "Error: No .log files found in '$LOG_DIR'"
    echo "Make sure you've unzipped the log files first:"
    echo "  cd $LOG_DIR"
    echo "  find . -name '*.gz' -exec gunzip {} \\;"
    exit 1
fi

echo "Converting ALB logs to GoAccess format..."
echo "Input directory: $LOG_DIR"
echo "Output file: $OUTPUT_FILE"
echo "Found $(echo "$LOG_FILES" | wc -l) log files"

# Convert ALB logs to Apache Combined Log format for GoAccess
find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk 'NF > 10 {
  # Extract and reformat timestamp to DD/MMM/YYYY:HH:MM:SS format
  iso_timestamp = $2
  gsub(/T/, " ", iso_timestamp)
  gsub(/\.[0-9]+Z/, "", iso_timestamp)
  
  # Parse the date components
  split(iso_timestamp, dt, " ")
  date_part = dt[1]
  time_part = dt[2]
  
  split(date_part, date_components, "-")
  year = date_components[1]
  month = date_components[2]
  day = date_components[3]
  
  # Convert month number to name
  months["01"] = "Jan"; months["02"] = "Feb"; months["03"] = "Mar"
  months["04"] = "Apr"; months["05"] = "May"; months["06"] = "Jun"
  months["07"] = "Jul"; months["08"] = "Aug"; months["09"] = "Sep"
  months["10"] = "Oct"; months["11"] = "Nov"; months["12"] = "Dec"
  
  formatted_timestamp = day "/" months[month] "/" year ":" time_part " +0000"
  
  # Extract IP (remove port)
  ip = $4
  gsub(/:.*/, "", ip)
  
  # Extract status code
  status = $9
  
  # Extract method, URL, and protocol from quoted field
  request_field = ""
  for(i=13; i<=15; i++) {
    if(i==13) request_field = $i
    else request_field = request_field " " $i
  }
  gsub(/^"/, "", request_field)
  gsub(/"$/, "", request_field)
  
  # Extract user agent
  user_agent = $16
  gsub(/^"/, "", user_agent)
  gsub(/"$/, "", user_agent)
  
  # Print in Apache combined log format
  print ip " - - [" formatted_timestamp "] \"" request_field "\" " status " 0 \"-\" \"" user_agent "\""
}' > "$OUTPUT_FILE"

# Check if conversion was successful
if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
    CONVERTED_LINES=$(wc -l < "$OUTPUT_FILE")
    echo "✅ Conversion completed successfully!"
    echo "📊 Converted $CONVERTED_LINES log entries"
    echo "📁 Output: $OUTPUT_FILE"
    echo ""
    echo "Next steps:"
    echo "  1. Generate GoAccess report: goaccess $OUTPUT_FILE --log-format=COMBINED -o output/elb_goaccess_report.html"
echo "  2. Open report: open output/elb_goaccess_report.html"
else
    echo "❌ Error: Conversion failed or no data was converted."
    exit 1
fi 