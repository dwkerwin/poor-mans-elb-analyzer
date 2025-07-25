#!/bin/bash

# Script to extract logs for specific URLs and status codes
# Usage: ./extract_url_logs.sh <status_pattern> <url_pattern> <output_file>

# Check if arguments are provided
if [ $# -ne 3 ]; then
    echo "Usage: $0 <status_pattern> <url_pattern> <output_file>"
    echo ""
    echo "Status Pattern Examples:"
    echo "  XXX  - Any status code"
    echo "  5XX  - Any 5xx error (500-599)"
    echo "  4XX  - Any 4xx error (400-499)"
    echo "  500  - Exact status code 500"
    echo "  404  - Exact status code 404"
    echo ""
    echo "Examples:"
    echo "  $0 \"5XX\" \"checkout/onepage/success\" output/checkout_5xx.csv"
    echo "  $0 \"500\" \"checkout/onepage/success\" output/checkout_500.csv"
    echo "  $0 \"4XX\" \"api/v1/\" output/api_4xx.csv"
    echo "  $0 \"XXX\" \"login\" output/all_login.csv"
    echo "  $0 \"404\" \"images/\" output/missing_images.csv"
    echo ""
    echo "The URL pattern will match any URL containing the specified string."
    echo "Output will be written to the specified CSV file."
    exit 1
fi

STATUS_PATTERN="$1"
URL_PATTERN="$2"
OUTPUT_FILE="$3"
LOG_DIR="elb-logs"

echo "🔍 Extracting logs for status pattern: $STATUS_PATTERN, URL pattern: $URL_PATTERN"
echo "📁 Log directory: $LOG_DIR"
echo "📄 Output file: $OUTPUT_FILE"
echo ""

# Check if log directory exists and has .log files
if [ ! -d "$LOG_DIR" ]; then
    echo "❌ Log directory '$LOG_DIR' not found."
    echo "Make sure you've downloaded and unzipped the ELB logs first."
    exit 1
fi

LOG_FILES=$(find "$LOG_DIR" -name "*.log" -type f)
if [ -z "$LOG_FILES" ]; then
    echo "❌ No .log files found in '$LOG_DIR'"
    echo "Make sure you've unzipped the log files first."
    exit 1
fi

# Create output directory if it doesn't exist
OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p "$OUTPUT_DIR"
    echo "📁 Created output directory: $OUTPUT_DIR"
fi

# Create CSV header
echo "Timestamp,Client_IP,Status_Code,Response_Time_ms,Backend_Response_Time_ms,Request_Method,Full_URL,User_Agent" > "$OUTPUT_FILE"

echo "🔍 Searching for logs matching status pattern and URL pattern..."

# Status code matching is handled directly in the AWK script

# Find all logs matching the criteria and extract relevant data
find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk -v pattern="$URL_PATTERN" -v status_pattern="$STATUS_PATTERN" '
{
    # Check if status code matches the pattern
    status_match = 0
    
    if (status_pattern == "XXX") {
        status_match = 1
    } else if (status_pattern == "5XX") {
        if ($9 >= 500 && $9 <= 599) status_match = 1
    } else if (status_pattern == "4XX") {
        if ($9 >= 400 && $9 <= 499) status_match = 1
    } else if (status_pattern == "3XX") {
        if ($9 >= 300 && $9 <= 399) status_match = 1
    } else if (status_pattern == "2XX") {
        if ($9 >= 200 && $9 <= 299) status_match = 1
    } else if (status_pattern == "1XX") {
        if ($9 >= 100 && $9 <= 199) status_match = 1
    } else {
        # Exact status code match
        if ($9 == status_pattern) status_match = 1
    }
    
    # Check if URL matches the pattern and status matches
    if (status_match && $14 ~ pattern) {
        # Extract timestamp and clean it up
        timestamp = $2
        gsub(/T/, " ", timestamp)
        gsub(/\.[0-9]+Z/, "", timestamp)
        
        # Extract client IP (remove port)
        client_ip = $4
        gsub(/:.*/, "", client_ip)
        
        # Status code
        status_code = $9
        
        # Response times (convert to milliseconds, handle - for missing values)
        elb_response_time = ($10 == "-") ? "N/A" : ($10 * 1000)
        backend_response_time = ($11 == "-") ? "N/A" : ($11 * 1000)
        
        # Request method
        request_method = $13
        gsub(/^"/, "", request_method)
        
        # Full URL
        full_url = $14
        gsub(/^"/, "", full_url)
        gsub(/"$/, "", full_url)
        
        # User agent (field 15, but might span multiple fields)
        user_agent = ""
        for(i=15; i<=NF; i++) {
            if(i==15) user_agent = $i
            else user_agent = user_agent " " $i
        }
        gsub(/^"/, "", user_agent)
        gsub(/"$/, "", user_agent)
        # Escape any commas in user agent for CSV
        gsub(/,/, ";", user_agent)
        
        # Print CSV row
        print timestamp "," client_ip "," status_code "," elb_response_time "," backend_response_time "," request_method "," full_url "," user_agent
    }
}' >> "$OUTPUT_FILE"

# Count the matches
TOTAL_MATCHES=$(tail -n +2 "$OUTPUT_FILE" | wc -l)

echo "✅ Extraction complete!"
echo ""
echo "📊 RESULTS:"
echo "==========="
echo "Total logs found: $TOTAL_MATCHES"
echo "Output saved to: $OUTPUT_FILE"
echo ""

if [ "$TOTAL_MATCHES" -gt 0 ]; then
    echo "🎯 QUICK STATS:"
    echo "==============="
    
    # Status code breakdown
    echo "Status Code Distribution:"
    tail -n +2 "$OUTPUT_FILE" | cut -d',' -f3 | sort | uniq -c | sort -nr | awk '{printf "  %s: %d entries\n", $2, $1}'
    echo ""
    
    # Top client IPs
    echo "Top Client IPs:"
    tail -n +2 "$OUTPUT_FILE" | cut -d',' -f2 | sort | uniq -c | sort -nr | head -5 | awk '{printf "  %s: %d entries\n", $2, $1}'
    echo ""
    
    # Response time stats (only for numeric values)
    echo "Response Time Analysis:"
    echo "  (Note: Only showing ELB response times, backend times may be N/A)"
    tail -n +2 "$OUTPUT_FILE" | cut -d',' -f4 | grep -E '^[0-9]+\.?[0-9]*$' | awk '
    {
        sum += $1
        if(NR == 1) {
            min = max = $1
        } else {
            if($1 < min) min = $1
            if($1 > max) max = $1
        }
        count++
    }
    END {
        if(count > 0) {
            avg = sum / count
            printf "  Average response time: %.2f ms\n", avg
            printf "  Min response time: %.2f ms\n", min
            printf "  Max response time: %.2f ms\n", max
        }
    }'
    echo ""
    
    echo "💡 NEXT STEPS:"
    echo "=============="
    echo "• Open the CSV file in Excel/Google Sheets for detailed analysis"
    echo "• Look for patterns in client IPs, response times, and timestamps"
    echo "• Check if specific user agents are causing issues"
    echo "• Correlate high response times with specific error patterns"
    echo ""
    echo "🔧 USEFUL COMMANDS:"
    echo "=================="
    echo "# View the CSV file:"
    echo "cat $OUTPUT_FILE"
    echo ""
    echo "# Sort by response time (descending):"
    echo "head -1 $OUTPUT_FILE && tail -n +2 $OUTPUT_FILE | sort -t',' -k4 -nr"
    echo ""
    echo "# Filter by specific status code (e.g., 500):"
    echo "head -1 $OUTPUT_FILE && tail -n +2 $OUTPUT_FILE | grep ',500,'"
    
else
    echo "ℹ️  No logs found matching status pattern: $STATUS_PATTERN and URL pattern: $URL_PATTERN"
    echo ""
    echo "💡 TROUBLESHOOTING:"
    echo "=================="
    echo "• Check that the status pattern is correct (XXX, 5XX, 4XX, or exact code like 500)"
    echo "• Check that the URL pattern is correct"
    echo "• Try a partial match (e.g., just 'checkout' instead of 'checkout/onepage/success')"
    echo "• Verify that your log files contain the expected data"
    echo "• Run ./analyze_5xx_errors.sh to see all available error URLs"
    echo "• Or use this script with '5XX' and '.' patterns to see all 5xx errors"
fi

echo ""
echo "Extraction complete! 🎉" 