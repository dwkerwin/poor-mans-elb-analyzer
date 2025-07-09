#!/bin/bash

# Default log directory
LOG_DIR="${1:-elb-logs}"

echo "🚨 5xx Server Error Analysis"
echo "=========================="
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

echo "📊 SUMMARY:"
echo "Total requests: $(find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | wc -l)"
echo "Total 5xx errors: $(find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '$9 >= 500 && $9 < 600' | wc -l)"
echo ""

echo "🔥 5xx ERRORS BY STATUS CODE AND URL:"
echo "====================================="
find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '$9 >= 500 && $9 < 600 {
    status = $9
    method_url = $13 " " $14
    gsub(/^"/, "", method_url)
    gsub(/"$/, "", method_url)
    key = status " | " method_url
    count[key]++
}
END {
    for (item in count) {
        print count[item], item
    }
}' | sort -nr | head -20 | awk '{
    count = $1
    status_url = ""
    for(i=2; i<=NF; i++) {
        if(i==2) status_url = $i
        else status_url = status_url " " $i
    }
    printf "%-6s %s\n", count, status_url
}'
echo ""

echo "🌐 5xx ERRORS BY IP ADDRESS:"
echo "============================"
find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '$9 >= 500 && $9 < 600 {
    ip = $4
    gsub(/:.*/, "", ip)
    count[ip]++
}
END {
    for (ip in count) {
        print count[ip], ip
    }
}' | sort -nr | head -15 | awk '{printf "%-6s %s\n", $1, $2}'
echo ""

echo "📈 5xx ERRORS BY STATUS CODE:"
echo "============================="
find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '$9 >= 500 && $9 < 600 {
    status = $9
    count[status]++
}
END {
    for (status in count) {
        print count[status], status
    }
}' | sort -nr | awk '{
    status_descriptions["500"] = "Internal Server Error"
    status_descriptions["501"] = "Not Implemented"
    status_descriptions["502"] = "Bad Gateway"
    status_descriptions["503"] = "Service Unavailable"
    status_descriptions["504"] = "Gateway Timeout"
    status_descriptions["505"] = "HTTP Version Not Supported"
    
    count = $1
    status = $2
    description = status_descriptions[status]
    if (description == "") description = "Unknown"
    
    printf "%-6s %s - %s\n", count, status, description
}'
echo ""

echo "⏰ 5xx ERRORS BY HOUR:"
echo "====================="
find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '$9 >= 500 && $9 < 600 {
    timestamp = $2
    gsub(/T/, " ", timestamp)
    gsub(/\.[0-9]+Z/, "", timestamp)
    split(timestamp, dt, " ")
    time_part = dt[2]
    split(time_part, time_components, ":")
    hour = time_components[1]
    count[hour]++
}
END {
    for (hour in count) {
        print hour, count[hour]
    }
}' | sort -k1 | awk '{printf "%s:00 - %s errors\n", $1, $2}'
echo ""

echo "🎯 TOP 10 PROBLEMATIC ENDPOINTS (5xx errors):"
echo "=============================================="
find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '$9 >= 500 && $9 < 600 {
    url = $14
    gsub(/^"/, "", url)
    gsub(/"$/, "", url)
    # Extract just the path (remove query parameters for grouping)
    gsub(/\?.*/, "", url)
    count[url]++
}
END {
    for (url in count) {
        print count[url], url
    }
}' | sort -nr | head -10 | awk '{printf "%-6s %s\n", $1, $2}'
echo ""

echo "🕐 RECENT 5xx ERRORS (Last 10):"
echo "==============================="
find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '$9 >= 500 && $9 < 600 {
    timestamp = $2
    ip = $4
    gsub(/:.*/, "", ip)
    status = $9
    method_url = $13 " " $14
    gsub(/^"/, "", method_url)
    gsub(/"$/, "", method_url)
    print timestamp, ip, status, method_url
}' | tail -10 | awk '{
    timestamp = $1
    gsub(/T/, " ", timestamp)
    gsub(/\.[0-9]+Z/, "", timestamp)
    ip = $2
    status = $3
    method_url = ""
    for(i=4; i<=NF; i++) {
        if(i==4) method_url = $i
        else method_url = method_url " " $i
    }
    printf "%-20s %-15s %-3s %s\n", timestamp, ip, status, method_url
}'
echo ""

echo "💡 RECOMMENDATIONS:"
echo "==================="

# Count unique 5xx errors
total_5xx=$(find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '$9 >= 500 && $9 < 600' | wc -l)
total_requests=$(find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | wc -l)

if [ "$total_5xx" -gt 0 ]; then
    error_rate=$(echo "scale=2; $total_5xx * 100 / $total_requests" | bc 2>/dev/null || echo "N/A")
    echo "• 5xx Error Rate: $error_rate% ($total_5xx out of $total_requests requests)"
    
    if [ "$total_5xx" -gt 100 ]; then
        echo "• ⚠️  HIGH: More than 100 server errors detected"
        echo "• Consider checking application logs and server health"
    elif [ "$total_5xx" -gt 10 ]; then
        echo "• ⚠️  MEDIUM: Moderate number of server errors"
        echo "• Monitor application performance and error patterns"
    else
        echo "• ✅ LOW: Relatively few server errors"
    fi
    
    # Check for specific patterns
    echo ""
    echo "🔍 PATTERN ANALYSIS:"
    echo "==================="
    
    # Check for 502 errors (common with load balancer issues)
    bad_gateway_count=$(find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '$9 == 502' | wc -l)
    if [ "$bad_gateway_count" -gt 0 ]; then
        echo "• Found $bad_gateway_count Bad Gateway (502) errors - check backend server health"
    fi
    
    # Check for 504 errors (timeouts)
    timeout_count=$(find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '$9 == 504' | wc -l)
    if [ "$timeout_count" -gt 0 ]; then
        echo "• Found $timeout_count Gateway Timeout (504) errors - check response times"
    fi
    
    # Check for 503 errors (service unavailable)
    unavailable_count=$(find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '$9 == 503' | wc -l)
    if [ "$unavailable_count" -gt 0 ]; then
        echo "• Found $unavailable_count Service Unavailable (503) errors - check service capacity"
    fi
    
else
    echo "• ✅ No 5xx errors found in the analyzed logs"
fi

echo ""
echo "📋 EXPORT OPTIONS:"
echo "=================="
echo "To export 5xx errors to CSV:"
echo "find \"$LOG_DIR\" -name \"*.log\" -type f -exec cat {} \\; | awk '\$9 >= 500 && \$9 < 600 {print \$2,\$4,\$9,\$13,\$14}' > 5xx_errors.csv"
echo ""
echo "To filter by specific status code (e.g., 502):"
echo "find \"$LOG_DIR\" -name \"*.log\" -type f -exec cat {} \\; | awk '\$9 == 502' > 502_errors.log"

echo ""
echo "Analysis complete! 🎉"
