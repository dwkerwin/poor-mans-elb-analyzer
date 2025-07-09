# Setting Up ELB Access Logging to S3

This guide walks you through enabling access logging for your AWS Elastic Load Balancer (ALB/NLB/CLB) to S3. If you already have this configured, you can skip to the main [README](README.md).

## Prerequisites

- AWS CLI configured with appropriate permissions
- An existing ELB (ALB, NLB, or Classic Load Balancer)
- An S3 bucket for storing logs (or permissions to create one)

## Step 1: Create or Configure S3 Bucket

### Option A: Create a New S3 Bucket
```bash
# Replace with your preferred bucket name and region
aws s3 mb s3://your-elb-logs-bucket-name --region us-east-1
```

### Option B: Use Existing S3 Bucket
If you already have a centralized logging bucket, you can use that.

## Step 2: Configure S3 Bucket Policy

Your S3 bucket needs a policy that allows the ELB service to write logs. The policy below uses both the AWS principal method (region-specific ELB account IDs) and the service principal method (AWS service names) to ensure compatibility across different AWS regions and ELB types.

### Find Your ELB Service Account ID

ELB service account IDs by region:
- **us-east-1**: 127311923021
- **us-east-2**: 033677994240
- **us-west-1**: 027434742980
- **us-west-2**: 797873946194
- **eu-west-1**: 156460612806
- **eu-central-1**: 054676820928
- **ap-southeast-1**: 114774131450
- **ap-southeast-2**: 783225319266

[Complete list of ELB service accounts](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-access-logging.html#attach-bucket-policy)

### Apply the Bucket Policy

Replace the placeholders and apply this policy to your S3 bucket:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ELB-SERVICE-ACCOUNT-ID:root"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::your-bucket-name/your-prefix/AWSLogs/YOUR-AWS-ACCOUNT-ID/*"
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "logdelivery.elasticloadbalancing.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::your-bucket-name/your-prefix/AWSLogs/YOUR-AWS-ACCOUNT-ID/*"
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "delivery.logs.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::your-bucket-name/your-prefix/AWSLogs/YOUR-AWS-ACCOUNT-ID/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control"
        }
      }
    },
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::ELB-SERVICE-ACCOUNT-ID:root"
      },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::your-bucket-name"
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "logdelivery.elasticloadbalancing.amazonaws.com"
      },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::your-bucket-name"
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "delivery.logs.amazonaws.com"
      },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::your-bucket-name"
    }
  ]
}
```

### Apply the Policy via AWS CLI
```bash
# Save the policy to a file first (bucket-policy.json), then:
aws s3api put-bucket-policy --bucket your-bucket-name --policy file://bucket-policy.json
```

### Apply the Policy via AWS Console
1. Go to S3 → Your bucket → Permissions → Bucket policy
2. Paste the JSON policy (with your values substituted)
3. Click "Save changes"

## Step 3: Enable Access Logging on Your ELB

### For Application Load Balancer (ALB) or Network Load Balancer (NLB):

1. **Go to EC2 Console** → Load Balancers
2. **Select your load balancer**
3. **Click the "Attributes" tab** (bottom panel)
4. **Find "Access logs"** in the attributes list
5. **Click "Edit"** next to Access logs
6. **Enable access logs** by checking the box
7. **Set S3 location**: `s3://your-bucket-name/your-prefix` 
   - Example: `s3://my-company-logs/production-alb`
8. **Click "Save changes"**

### For Classic Load Balancer (CLB):

1. **Go to EC2 Console** → Load Balancers
2. **Select your classic load balancer**
3. **Go to Description tab** → scroll down
4. **Find "Access logs"** section  
5. **Click "Configure Access Logs"**
6. **Enable access logs**
7. **Specify S3 location**: `your-bucket-name/your-prefix`
8. **Click "Save"**

### Via AWS CLI (ALB/NLB):
```bash
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn arn:aws:elasticloadbalancing:region:account:loadbalancer/app/my-load-balancer/1234567890123456 \
  --attributes Key=access_logs.s3.enabled,Value=true Key=access_logs.s3.bucket,Value=your-bucket-name Key=access_logs.s3.prefix,Value=your-prefix
```

## Step 4: Verify Logging is Working

After enabling access logging, it may take 5-10 minutes for logs to start appearing.

### Check S3 for Log Files
```bash
aws s3 ls s3://your-bucket-name/your-prefix/ --recursive
```

You should see a directory structure like:
```
your-prefix/AWSLogs/YOUR-ACCOUNT-ID/elasticloadbalancing/us-east-1/2025/01/08/
```

### Generate Some Traffic
Send a few requests to your load balancer to generate log entries, then check S3 again.

## Step 5: Note Your Configuration

Write down these values for use with the Poor Man's ELB Analyzer:
- **S3 Bucket Name**: `your-bucket-name`
- **ELB Log Prefix**: `your-prefix` (this becomes your `ELB_LOG_PREFIX`)
- **AWS Account ID**: Your 12-digit account ID
- **AWS Region**: Where your ELB is located

## Troubleshooting

### No logs appearing after 15+ minutes:
1. **Check bucket policy** - Ensure the ELB service account ID is correct for your region
2. **Check S3 path** - Make sure the bucket name and prefix are correct
3. **Check ELB traffic** - Logs only appear when there's actual traffic
4. **Check CloudTrail** - Look for any access denied errors

### Permission errors:
1. **Verify bucket policy** includes both PutObject and GetBucketAcl permissions
2. **Check AWS account ID** in the policy matches your account
3. **Verify ELB service account ID** matches your region

### Wrong log location:
1. **Check ELB configuration** - Verify the S3 path in load balancer attributes
2. **Check bucket policy** - Ensure the Resource ARN matches your actual path

## Next Steps

Once you have access logging working and can see log files in S3, you're ready to use the Poor Man's ELB Analyzer! 

👉 **Continue to the main [README](README.md)** to start analyzing your logs.

## Cost Considerations

- **S3 storage costs**: ELB logs are typically small, but they add up over time
- **S3 requests**: Each log file written incurs a PUT request charge
- **Consider lifecycle policies**: Archive or delete old logs to manage costs

For typical workloads, ELB logging costs are usually under $10-50/month depending on traffic volume. 