# Poor Man's ELB Analyzer

A lightweight solution for analyzing AWS Elastic Load Balancer (ALB/ELB/NLB) access logs when you don't have a proper log aggregator like Splunk or Sumologic. If your ELB logs are stored in S3 but you need to quickly analyze them without expensive tooling, this is a quick and dirty solution.

This toolkit provides:
- **GoAccess integration** - Beautiful HTML dashboards with interactive charts and graphs
- **Custom analysis scripts** - Command-line tools for specific analysis like 5xx error deep-dives, top IPs, and endpoint performance
- **Simple setup** - Just a few commands to download logs from S3 and generate reports

Much better than manually reviewing log files one at a time in a text editor, a workable solution for cost conscious teams who need occasional log analysis without the overhead of enterprise logging solutions.

## ⚠️ First Time Setup

**Don't have ELB access logging configured yet?** You'll need to set up logging from your ELB to S3 first.

👉 **[Follow our setup guide](setup-elb-s3-logging.md)** to configure ELB access logging to S3, then come back here.

## Prerequisites

- AWS CLI configured with appropriate credentials
- GoAccess installed (`brew install goaccess`)
- Access to the S3 bucket containing ELB logs

## Quick Start

### 1. Find Your S3 Log Path

First, you need to find where your ELB logs are stored in S3:

```bash
# Set your basic AWS info (you'll know these)
export AWS_PROFILE=your-aws-profile-name
export S3_BUCKET_NAME=your-centralized-logs-bucket-name

# List your S3 bucket to find the ELB log prefix
aws s3 ls s3://${S3_BUCKET_NAME}/ --profile $AWS_PROFILE
```

Look for a directory structure like:
```
your-bucket-name/
└── your-elb-log-prefix/AWSLogs/YOUR_ACCOUNT_ID/elasticloadbalancing/us-east-1/
```

The `your-elb-log-prefix` part is what you'll use for the `ELB_LOG_PREFIX` variable below.

### 2. Set Your AWS Configuration

Now that you know your ELB log prefix, configure your environment:

**Option A: Use the .env file for variables (recommended)**
```bash
# Copy .env.example to .env and update with your values
cp .env.example .env
# Edit .env with your actual values (including the ELB_LOG_PREFIX you found above)
# Then source it:
source .env
```

**Option B: Set environment variables manually**
```bash
export AWS_PROFILE=your-aws-profile-name
export S3_BUCKET_NAME=your-centralized-logs-bucket-name
export AWS_ACCOUNT_ID=123456789012
export AWS_REGION=us-east-1
export ELB_LOG_PREFIX=your-elb-log-prefix-from-step-1
```

**Note**: All commands use the explicit `--profile $AWS_PROFILE` flag since the AWS_PROFILE environment variable alone can be unreliable with AWS CLI.

### 3. Download Today's Logs
```bash
# Create directory
mkdir -p elb-logs

# Download today's logs
TODAY=$(date +%Y/%m/%d)
aws s3 sync s3://${S3_BUCKET_NAME}/${ELB_LOG_PREFIX}/AWSLogs/${AWS_ACCOUNT_ID}/elasticloadbalancing/${AWS_REGION}/$TODAY/ elb-logs/${ELB_LOG_PREFIX}/ --profile $AWS_PROFILE
```

### 4. Download Logs for Other Time Periods

#### Yesterday's Logs
```bash
YESTERDAY=$(date -v-1d +%Y/%m/%d)
aws s3 sync s3://${S3_BUCKET_NAME}/${ELB_LOG_PREFIX}/AWSLogs/${AWS_ACCOUNT_ID}/elasticloadbalancing/${AWS_REGION}/$YESTERDAY/ elb-logs/${ELB_LOG_PREFIX}/ --profile $AWS_PROFILE
```

#### Specific Date
```bash
SPECIFIC_DATE="2025/07/07"  # Format: YYYY/MM/DD
aws s3 sync s3://${S3_BUCKET_NAME}/${ELB_LOG_PREFIX}/AWSLogs/${AWS_ACCOUNT_ID}/elasticloadbalancing/${AWS_REGION}/$SPECIFIC_DATE/ elb-logs/${ELB_LOG_PREFIX}/ --profile $AWS_PROFILE
```

#### Last 7 Days (requires multiple commands)
```bash
for i in {0..6}; do
  DATE=$(date -v-${i}d +%Y/%m/%d)
  echo "Downloading logs for $DATE..."
  aws s3 sync s3://${S3_BUCKET_NAME}/${ELB_LOG_PREFIX}/AWSLogs/${AWS_ACCOUNT_ID}/elasticloadbalancing/${AWS_REGION}/$DATE/ elb-logs/${ELB_LOG_PREFIX}/ --profile $AWS_PROFILE
done
```

### 5. Unzip All Log Files
```bash
find elb-logs -name "*.gz" -exec gunzip {} \;
```

### 6. Convert to GoAccess Format
```bash
# Convert ALB logs to Apache Combined Log format for GoAccess
./convert_to_goaccess.sh

# Or specify custom directory and output file:
# ./convert_to_goaccess.sh elb-logs my_converted_logs.log
```

### 7. Generate GoAccess Report
```bash
goaccess elb_converted.log --log-format=COMBINED -o elb_goaccess_report.html
```

### 8. Open the Report
```bash
open elb_goaccess_report.html
```

## Analysis Scripts

### Basic Analysis Script
Run `./simple_analysis.sh` for basic statistics including:
- Total requests and log files
- Top client IPs
- Status code distribution
- Top endpoints
- Error requests (4xx/5xx)
- Requests by hour

**Usage**: `./simple_analysis.sh [log_directory]`  
Default log directory is `elb-logs` if not specified.

### 5xx Error Analysis Script
Run `./analyze_5xx_errors.sh` for detailed server error analysis:
- 5xx errors by status code and URL
- 5xx errors by IP address
- Timeline of server errors
- Most problematic endpoints

**Usage**: `./analyze_5xx_errors.sh [log_directory]`  
Default log directory is `elb-logs` if not specified.

## Understanding the GoAccess Dashboard

The generated HTML report includes:

- **General Statistics**: Overview of total requests, unique visitors, bandwidth
- **Top Requests**: Most frequently accessed URLs
- **Static Requests**: CSS, JS, images, etc.
- **Not Found URLs**: 404 errors
- **Hosts**: Top visitor IP addresses with geographic data
- **Operating Systems**: Visitor OS breakdown
- **Browsers**: User agent analysis
- **Time Distribution**: Traffic patterns over time
- **HTTP Status Codes**: Response code distribution
- **Referrers**: Where traffic is coming from
- **Keyphrases**: Search terms (if available)



## Advanced Usage

### Analyzing Multiple Days
To analyze logs from multiple days, download them all to the same directory before running the conversion script.

### Multiple ELBs
If you have multiple ELBs to analyze, run the tool separately for each one by changing the `ELB_LOG_PREFIX` variable, or download to different subdirectories.

### Real-time Monitoring
For real-time log analysis, you can set up GoAccess to monitor logs as they're written:
```bash
goaccess elb_converted.log --log-format=COMBINED -o elb_goaccess_report.html --real-time-html
```

### Custom Time Ranges
You can filter the converted logs by time range before running GoAccess:
```bash
# Filter logs for specific hour range
grep "08/Jul/2025:1[0-5]:" elb_converted.log > filtered_logs.log
goaccess filtered_logs.log --log-format=COMBINED -o filtered_report.html
```

 