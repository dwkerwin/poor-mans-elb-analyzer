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

### Setting up the AWS CLI

If you don't have the AWS CLI set up yet, here’s a quick guide for macOS:

1.  **Install the AWS CLI**: The easiest way is using [Homebrew](https://brew.sh/):
    ```bash
    brew install awscli
    ```
    For other installation options, see the [official AWS CLI installation guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).

2.  **Configure Your Credentials**: To connect to your AWS account, run `aws configure`. This command will create a `~/.aws/credentials` file to securely store your keys. You'll need an AWS Access Key ID and Secret Access Key.
    ```bash
    # Use the --profile flag to create a named profile
    # This is useful if you manage multiple AWS accounts
    aws configure --profile your-aws-profile-name
    ```
    The command will prompt you to enter your credentials:
    ```
    AWS Access Key ID [None]: YOUR_ACCESS_KEY_ID
    AWS Secret Access Key [None]: YOUR_SECRET_ACCESS_KEY
    Default region name [None]: us-east-1
    Default output format [None]: json
    ```
    Make sure the profile name you use here (`your-aws-profile-name`) matches the `AWS_PROFILE` you set in your `.env` file or export as an environment variable.

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
goaccess elb_converted.log --log-format=COMBINED -o output/elb_goaccess_report.html
```

### 8. Open the Report
```bash
open output/elb_goaccess_report.html
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

### URL-Specific Log Extraction Script
Run `./extract_url_logs.sh` for detailed extraction of logs matching specific status codes and URLs:
- Flexible status code patterns (5XX, 4XX, exact codes like 500, or XXX for all)
- Detailed CSV output with timestamp, IP, status code, response times, and user agent
- Automatic URL pattern matching (e.g., "checkout" matches any URL containing "checkout")
- Response time analysis and quick statistics
- Perfect for analyzing critical endpoints, error patterns, or specific user flows

**Usage**: `./extract_url_logs.sh "<status_pattern>" "<url_pattern>" "<output_file>"`

**Examples**:
```bash
# Extract 5xx errors for checkout
./extract_url_logs.sh "5XX" "checkout/onepage/success" output/checkout_5xx.csv

# Extract exact 500 errors for checkout
./extract_url_logs.sh "500" "checkout/onepage/success" output/checkout_500.csv

# Extract 4xx errors for API endpoints
./extract_url_logs.sh "4XX" "api/v1/" output/api_4xx.csv

# Extract all requests for login pages
./extract_url_logs.sh "XXX" "login" output/all_login.csv

# Extract 404 errors for missing images
./extract_url_logs.sh "404" "images/" output/missing_images.csv
```

**Status Pattern Options**:
- `XXX` - Any status code
- `5XX` - Any 5xx error (500-599)  
- `4XX` - Any 4xx error (400-499)
- `3XX` - Any 3xx redirect (300-399)
- `2XX` - Any 2xx success (200-299)
- `500` - Exact status code (500, 404, etc.)

The output CSV includes:
- Timestamp
- Client IP address
- HTTP status code
- ELB response time (milliseconds)
- Backend response time (milliseconds)
- Request method (GET, POST, etc.)
- Full URL with parameters
- User agent string

### E-Commerce Checkout Analysis Script (Python)
Run `python3 ecommerce_checkout_analysis.py` for comprehensive e-commerce checkout and cart error analysis:
- **Revenue-focused analysis** - Zeroes in on cart, checkout, payment, and order-related errors
- **Daily trend analysis** - Shows if checkout errors are increasing over time with day-by-day breakdown
- **Hourly patterns** - Identifies peak error hours and problematic time periods  
- **Checkout funnel breakdown** - Analyzes errors by stage (cart → shipping → payment → completion)
- **Bot vs human traffic** - Distinguishes automated vs real customer errors
- **Mobile vs desktop** - Identifies platform-specific issues
- **Performance correlation** - Links slow response times to checkout errors
- **Actionable recommendations** - Provides specific suggestions based on your data patterns

**Python Requirements**: Python 3.7+ (tested with Python 3.13.3)
- **No additional setup required** - Uses only Python standard library modules
- **No virtual environment needed** - All dependencies are built-in to Python

**Usage**: 
```bash
# Basic analysis (outputs to screen)
python3 ecommerce_checkout_analysis.py

# Analyze specific directory
python3 ecommerce_checkout_analysis.py elb-logs

# Save output to file (in addition to screen display)
python3 ecommerce_checkout_analysis.py elb-logs --output checkout_analysis.txt

# Save to specific location
python3 ecommerce_checkout_analysis.py elb-logs --output /tmp/checkout_analysis.log
```

**Key Features**:
- Automatically detects checkout-related URL patterns (cart, payment, paypal, stripe, checkout, etc.)
- Analyzes 5xx (server) errors with detailed breakdowns
- Tracks error trends over time to identify if problems are getting worse
- Categorizes errors by checkout funnel stage to pinpoint problem areas
- Identifies bot traffic that might be skewing error rates
- Provides performance analysis to find slow checkout processes
- Generates actionable recommendations based on your specific data patterns

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
goaccess elb_converted.log --log-format=COMBINED -o output/elb_goaccess_report.html --real-time-html
```

### Custom Time Ranges
You can filter the converted logs by time range before running GoAccess:
```bash
# Filter logs for specific hour range
grep "08/Jul/2025:1[0-5]:" elb_converted.log > filtered_logs.log
goaccess filtered_logs.log --log-format=COMBINED -o output/filtered_report.html
```

 