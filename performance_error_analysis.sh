#!/bin/bash

# ALB Performance & Error Analysis Script
# Analyzes response times, percentiles, errors, and slow endpoints
# Usage: ./performance_error_analysis.sh [log_directory]

# Default log directory
LOG_DIR="${1:-elb-logs}"

echo "🚀 ALB Performance & Error Analysis"
echo "==================================="
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

echo "📁 Found $(echo "$LOG_FILES" | wc -l) log files"
echo ""

# Create temporary files for analysis
TEMP_RESPONSE_TIMES=$(mktemp)
TEMP_ERROR_ANALYSIS=$(mktemp)
TEMP_URL_TIMES=$(mktemp)

# Extract response time data and error data
echo "🔍 Processing logs..."
find "$LOG_DIR" -name "*.log" -type f -exec cat {} \; | awk '{
    # Calculate total response time (request_processing + target_processing + response_processing)
    total_response_time = ($6 + $7 + $8) * 1000  # Convert to milliseconds
    target_response_time = $7 * 1000  # Backend response time in milliseconds
    status_code = $9
    
    # Extract URL from field 14 (the actual URL field)
    url = $14
    gsub(/^"/, "", url)  # Remove leading quote
    gsub(/"$/, "", url)  # Remove trailing quote
    gsub(/\?.*/, "", url)  # Remove query parameters for grouping
    
    # Print response time data
    print total_response_time, target_response_time, status_code, url
}' > "$TEMP_RESPONSE_TIMES"

TOTAL_REQUESTS=$(wc -l < "$TEMP_RESPONSE_TIMES")

echo "📊 OVERALL STATISTICS"
echo "===================="
echo "Total requests analyzed: $TOTAL_REQUESTS"
echo ""

# Calculate response time statistics
echo "⏱️  RESPONSE TIME ANALYSIS"
echo "=========================="

# Calculate average, min, max response times
awk '{
    total_sum += $1
    backend_sum += $2
    if(NR == 1) {
        total_min = total_max = $1
        backend_min = backend_max = $2
    } else {
        if($1 < total_min) total_min = $1
        if($1 > total_max) total_max = $1
        if($2 < backend_min) backend_min = $2
        if($2 > backend_max) backend_max = $2
    }
}
END {
    if(NR > 0) {
        printf "Average total response time: %.2f ms\n", total_sum / NR
        printf "Average backend response time: %.2f ms\n", backend_sum / NR
        printf "Min total response time: %.2f ms\n", total_min
        printf "Max total response time: %.2f ms\n", total_max
        printf "Min backend response time: %.2f ms\n", backend_min
        printf "Max backend response time: %.2f ms\n", backend_max
    }
}' "$TEMP_RESPONSE_TIMES"

echo ""

# Calculate 95th percentile (top 5% slowest)
echo "📈 PERCENTILE ANALYSIS"
echo "====================="

# Sort by total response time and calculate percentiles
sort -n "$TEMP_RESPONSE_TIMES" | awk -v total="$TOTAL_REQUESTS" '
{
    response_times[NR] = $1
    backend_times[NR] = $2
}
END {
    # Calculate percentile positions
    p50_pos = int(total * 0.5)
    p75_pos = int(total * 0.75)
    p90_pos = int(total * 0.9)
    p95_pos = int(total * 0.95)
    p99_pos = int(total * 0.99)
    
    if(p50_pos == 0) p50_pos = 1
    if(p75_pos == 0) p75_pos = 1
    if(p90_pos == 0) p90_pos = 1
    if(p95_pos == 0) p95_pos = 1
    if(p99_pos == 0) p99_pos = 1
    
    printf "50th percentile (median): %.2f ms\n", response_times[p50_pos]
    printf "75th percentile: %.2f ms\n", response_times[p75_pos]
    printf "90th percentile: %.2f ms\n", response_times[p90_pos]
    printf "95th percentile: %.2f ms (top 5%% slowest)\n", response_times[p95_pos]
    printf "99th percentile: %.2f ms\n", response_times[p99_pos]
}'

echo ""

# Error Analysis
echo "🚨 5XX ERROR ANALYSIS"
echo "====================="

# Count errors by status code
awk '$3 >= 500 && $3 < 600 {
    status = $3
    count[status]++
    total_errors++
}
END {
    if(total_errors > 0) {
        printf "Total 5xx error requests: %d\n", total_errors
        printf "5xx error rate: %.2f%%\n\n", (total_errors / total_requests * 100)
        
        printf "Error breakdown:\n"
        for (status in count) {
            printf "  %s: %d (%.1f%%)\n", status, count[status], (count[status] / total_errors * 100)
        }
    } else {
        printf "No 5xx errors found\n"
    }
}' total_requests="$TOTAL_REQUESTS" "$TEMP_RESPONSE_TIMES"

echo ""

# Top 10 High Error URLs
echo "🎯 TOP 10 HIGH 5XX ERROR URLS"
echo "=============================="

awk '$3 >= 500 && $3 < 600 {
    url = $4
    error_count[url]++
}
END {
    for (url in error_count) {
        print error_count[url], url
    }
}' "$TEMP_RESPONSE_TIMES" | sort -nr | head -10 | awk '{
    printf "%-6s %s\n", $1, $2
}'

echo ""

# Top 10 Slowest URLs by Average Response Time
echo "🐌 TOP 10 SLOWEST URLS (by average response time)"
echo "================================================"

awk '{
    url = $4
    total_time[url] += $1
    count[url]++
}
END {
    for (url in total_time) {
        avg_time = total_time[url] / count[url]
        printf "%.2f %d %s\n", avg_time, count[url], url
    }
}' "$TEMP_RESPONSE_TIMES" | sort -nr | head -10 | awk '{
    printf "%-8.2f ms (%-4s requests) %s\n", $1, $2, $3
}'

echo ""

# Top 10 URLs with Most Requests Over 1 Second
echo "⏰ TOP 10 URLS WITH MOST SLOW REQUESTS (>1000ms)"
echo "==============================================="

awk '$1 > 1000 {
    url = $4
    slow_count[url]++
    slow_time_sum[url] += $1
}
END {
    for (url in slow_count) {
        avg_slow_time = slow_time_sum[url] / slow_count[url]
        printf "%d %.2f %s\n", slow_count[url], avg_slow_time, url
    }
}' "$TEMP_RESPONSE_TIMES" | sort -nr | head -10 | awk '{
    printf "%-6s slow requests (avg: %-8.2f ms) %s\n", $1, $2, $3
}'

echo ""

# Response Time Distribution
echo "📊 RESPONSE TIME DISTRIBUTION"
echo "============================="

awk '{
    total_time = $1
    if(total_time < 100) bucket_0_100++
    else if(total_time < 250) bucket_100_250++
    else if(total_time < 500) bucket_250_500++
    else if(total_time < 1000) bucket_500_1000++
    else if(total_time < 2000) bucket_1000_2000++
    else if(total_time < 5000) bucket_2000_5000++
    else bucket_5000_plus++
}
END {
    printf "< 100ms:      %-6s (%.1f%%)\n", bucket_0_100, (bucket_0_100/NR*100)
    printf "100-250ms:    %-6s (%.1f%%)\n", bucket_100_250, (bucket_100_250/NR*100)
    printf "250-500ms:    %-6s (%.1f%%)\n", bucket_250_500, (bucket_250_500/NR*100)
    printf "500ms-1s:     %-6s (%.1f%%)\n", bucket_500_1000, (bucket_500_1000/NR*100)
    printf "1-2s:         %-6s (%.1f%%)\n", bucket_1000_2000, (bucket_1000_2000/NR*100)
    printf "2-5s:         %-6s (%.1f%%)\n", bucket_2000_5000, (bucket_2000_5000/NR*100)
    printf "> 5s:         %-6s (%.1f%%)\n", bucket_5000_plus, (bucket_5000_plus/NR*100)
}' "$TEMP_RESPONSE_TIMES"

echo ""

# Backend vs Total Response Time Analysis
echo "🔄 BACKEND vs TOTAL RESPONSE TIME"
echo "================================="

awk '{
    backend_time = $2
    total_time = $1
    elb_overhead = total_time - backend_time
    
    backend_sum += backend_time
    total_sum += total_time
    overhead_sum += elb_overhead
}
END {
    if(NR > 0) {
        printf "Average backend processing: %.2f ms\n", backend_sum / NR
        printf "Average total response: %.2f ms\n", total_sum / NR
        printf "Average ELB overhead: %.2f ms\n", overhead_sum / NR
        printf "Backend processing ratio: %.1f%%\n", (backend_sum / total_sum * 100)
    }
}' "$TEMP_RESPONSE_TIMES"

echo ""

# Recommendations
echo "💡 RECOMMENDATIONS"
echo "=================="

# Calculate some metrics for recommendations
ERROR_RATE=$(awk '$3 >= 500 && $3 < 600 {errors++} END {printf "%.2f", (errors/NR*100)}' "$TEMP_RESPONSE_TIMES")
P95_TIME=$(sort -n "$TEMP_RESPONSE_TIMES" | awk -v total="$TOTAL_REQUESTS" 'END {pos = int(total * 0.95); if(pos == 0) pos = 1} NR == pos {print $1}')
SLOW_REQUESTS=$(awk '$1 > 1000 {count++} END {printf "%d", count+0}' "$TEMP_RESPONSE_TIMES")

echo "• 5xx Error Rate: $ERROR_RATE%"
if (( $(echo "$ERROR_RATE > 1.0" | bc -l 2>/dev/null || echo "0") )); then
    echo "  ⚠️  HIGH: 5xx error rate above 1% - investigate failing endpoints"
elif (( $(echo "$ERROR_RATE > 0.1" | bc -l 2>/dev/null || echo "0") )); then
    echo "  ⚠️  MODERATE: 5xx error rate above 0.1% - monitor error trends"
else
    echo "  ✅ GOOD: Low 5xx error rate"
fi

echo "• 95th Percentile Response Time: ${P95_TIME:-N/A} ms"
if [ -n "$P95_TIME" ] && (( $(echo "$P95_TIME > 2000" | bc -l 2>/dev/null || echo "0") )); then
    echo "  ⚠️  HIGH: 95th percentile above 2 seconds - optimize slow endpoints"
elif [ -n "$P95_TIME" ] && (( $(echo "$P95_TIME > 1000" | bc -l 2>/dev/null || echo "0") )); then
    echo "  ⚠️  MODERATE: 95th percentile above 1 second - consider performance improvements"
else
    echo "  ✅ GOOD: Reasonable 95th percentile response times"
fi

echo "• Slow Requests (>1s): ${SLOW_REQUESTS:-0}"
if [ "$SLOW_REQUESTS" -gt 100 ]; then
    echo "  ⚠️  HIGH: Many requests over 1 second - focus on slow endpoint optimization"
elif [ "$SLOW_REQUESTS" -gt 10 ]; then
    echo "  ⚠️  MODERATE: Some slow requests - investigate slowest endpoints"
else
    echo "  ✅ GOOD: Few slow requests"
fi

echo ""
echo "📋 EXPORT COMMANDS"
echo "=================="
echo "# Export 5xx error requests to CSV:"
echo "awk '\$3 >= 500 && \$3 < 600 {printf \"%s,%.2f,%s,%s\\n\", \$3, \$1, \$4, \"5xx_error\"}' $TEMP_RESPONSE_TIMES > 5xx_error_requests.csv"
echo ""
echo "# Export slow requests (>1s) to CSV:"
echo "awk '\$1 > 1000 {printf \"%.2f,%s,%s,slow\\n\", \$1, \$3, \$4}' $TEMP_RESPONSE_TIMES > slow_requests.csv"
echo ""
echo "# Export 95th percentile requests to CSV:"
echo "sort -n $TEMP_RESPONSE_TIMES | tail -n \$(echo \"$TOTAL_REQUESTS * 0.05\" | bc | cut -d. -f1) > p95_requests.csv"

# Cleanup
rm -f "$TEMP_RESPONSE_TIMES" "$TEMP_ERROR_ANALYSIS" "$TEMP_URL_TIMES"

echo ""
echo "Analysis complete! 🎉" 