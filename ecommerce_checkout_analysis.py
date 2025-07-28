#!/usr/bin/env python3
"""
E-Commerce Checkout & Cart Error Analysis Script
================================================

PURPOSE:
This script analyzes checkout and shopping cart related errors (4xx and 5xx) 
to help e-commerce store owners understand stability issues in their most 
critical revenue-generating processes.

SCOPE:
- Focuses on checkout, cart, payment, billing, shipping, and order-related URLs
- Analyzes both 4xx (client errors) and 5xx (server errors) 
- Provides daily and hourly trend analysis to identify if issues are worsening
- Examines user agents to distinguish bot vs human traffic
- Works exclusively with ELB log data (no external revenue/business data)

Requirements: Python 3.7+
"""

import argparse
import glob
import os
import re
import sys
from collections import defaultdict, Counter
from datetime import datetime, timedelta
from urllib.parse import urlparse, parse_qs
import ipaddress


class CheckoutAnalyzer:
    def __init__(self, log_dir, output_file=None):
        self.log_dir = log_dir
        self.output_file = output_file
        self.log_files = []
        # Focus ONLY on actual checkout flow - things that prevent purchase completion
        self.checkout_patterns = [
            # Shopping cart operations
            '/cart/', '/shopping-cart/', '/basket/', '/bag/', 'checkout/cart', 
            'cart/add', 'cart/update', 'cart/remove',
            
            # Checkout process
            '/checkout/', 'checkout/', 'onepage', 'guest-checkout', 'checkout/onepage',
            'checkout/success', 'checkout/complete', 'checkout/review', 'checkout/billing',
            'checkout/shipping', 'checkout/payment',
            
            # Payment processing (actual payment gateways and processing)
            '/payment/', '/pay/', 'paypal', 'stripe', 'amazon-pay', 'amazonpay', 
            'apple-pay', 'applepay', 'google-pay', 'googlepay', 'klarna', 'afterpay', 
            'affirm', '/billing/', 'credit-card', 'creditcard',
            
            # Order completion and confirmation
            '/order/', '/orders/', 'order/success', 'order/complete', 'order/confirmation',
            'order-confirmation', 'checkout/success', 'thank-you', 'thankyou',
            'receipt', 'order-receipt'
        ]
        
        # Compile regex pattern for checkout URLs
        self.checkout_regex = re.compile(
            r'(?i)(?:' + '|'.join(self.checkout_patterns) + r')',
            re.IGNORECASE
        )
        
        # Bot detection patterns
        self.bot_patterns = [
            'bot', 'crawler', 'spider', 'scraper', 'curl', 'wget', 'python', 'java',
            'http_request', 'postman', 'insomnia', 'user-agent', 'test', 'monitor',
            'uptime', 'pingdom', 'datadog', 'newrelic', 'googlebot', 'bingbot', 
            'facebookexternalhit', 'twitterbot', 'linkedinbot', 'whatsapp', 'telegram'
        ]
        self.bot_regex = re.compile(r'(?i)(?:' + '|'.join(self.bot_patterns) + r')')
        
        # Mobile detection patterns
        self.mobile_patterns = [
            'mobile', 'android', 'iphone', 'ipad', 'tablet', 'phone'
        ]
        self.mobile_regex = re.compile(r'(?i)(?:' + '|'.join(self.mobile_patterns) + r')')

    def log(self, message):
        """Print to stdout and optionally to file"""
        print(message)
        if self.output_file:
            with open(self.output_file, 'a', encoding='utf-8') as f:
                f.write(message + '\n')

    def validate_log_directory(self):
        """Validate log directory and find log files"""
        if not os.path.isdir(self.log_dir):
            raise FileNotFoundError(f"Log directory '{self.log_dir}' not found.")
        
        self.log_files = glob.glob(os.path.join(self.log_dir, "*.log"))
        if not self.log_files:
            raise FileNotFoundError(f"No .log files found in '{self.log_dir}'. Make sure you've unzipped the log files first.")

    def parse_log_line(self, line):
        """Parse ELB log line and return structured data"""
        try:
            # ELB logs have quoted fields, so we need to parse them carefully
            # Use regex to properly parse quoted fields
            # ELB log format: type time elb client:port target:port request_processing_time target_processing_time response_processing_time elb_status_code target_status_code received_bytes sent_bytes "request" "user_agent" ssl_cipher ssl_protocol
            pattern = r'(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+"([^"]*)"\s+"([^"]*)"\s+(\S+)\s+(\S+)'
            
            match = re.match(pattern, line)
            if not match:
                return None
            
            groups = match.groups()
            if len(groups) < 16:
                return None
                
            return {
                'timestamp': groups[1],
                'client_ip': groups[3].split(':')[0],
                'target_ip': groups[4].split(':')[0] if groups[4] != '-' else None,
                'request_processing_time': float(groups[5]) if groups[5] != '-1' else -1,
                'backend_processing_time': float(groups[6]) if groups[6] != '-1' else -1,
                'response_processing_time': float(groups[7]) if groups[7] != '-1' else -1,
                'elb_status_code': int(groups[8]) if groups[8] != '-' else None,
                'backend_status_code': int(groups[9]) if groups[9] != '-' else None,
                'received_bytes': int(groups[10]) if groups[10] != '-' else 0,
                'sent_bytes': int(groups[11]) if groups[11] != '-' else 0,
                'request': groups[12],
                'user_agent': groups[13],
                'ssl_cipher': groups[14] if groups[14] != '-' else '',
                'ssl_protocol': groups[15] if groups[15] != '-' else ''
            }
        except (ValueError, IndexError, AttributeError):
            return None

    def is_checkout_related(self, url):
        """Check if URL is checkout-related"""
        return bool(self.checkout_regex.search(url))

    def get_pattern_category(self, url):
        """Determine which checkout funnel stage this URL represents"""
        url_lower = url.lower()
        
        # Cart operations
        if any(term in url_lower for term in ['/cart/', 'cart/add', 'cart/update', 'cart/remove', '/basket/', '/bag/']):
            return 'Shopping Cart'
        
        # Payment processing
        elif any(term in url_lower for term in ['paypal', 'stripe', 'amazon-pay', 'apple-pay', 'google-pay', 'klarna', 'afterpay', 'affirm', '/payment/', '/pay/', '/billing/', 'credit-card']):
            return 'Payment Processing'
        
        # Order completion
        elif any(term in url_lower for term in ['/order/', '/orders/', 'order/success', 'order/complete', 'checkout/success', 'thank-you', 'thankyou', 'receipt', 'confirmation']):
            return 'Order Completion'
        
        # General checkout process
        elif any(term in url_lower for term in ['/checkout/', 'checkout/', 'onepage', 'guest-checkout']):
            return 'Checkout Process'
        
        return 'Other Checkout'

    def is_bot_traffic(self, user_agent):
        """Check if user agent indicates bot traffic"""
        return bool(self.bot_regex.search(user_agent))

    def is_mobile_traffic(self, user_agent):
        """Check if user agent indicates mobile traffic"""
        return bool(self.mobile_regex.search(user_agent))

    def categorize_checkout_stage(self, url):
        """Categorize checkout URL by funnel stage"""
        url_lower = url.lower()
        
        if any(term in url_lower for term in ['cart', 'basket', 'bag', 'shopping-cart']):
            return 'Cart Operations'
        elif any(term in url_lower for term in ['checkout/start', 'checkout/begin', 'checkout/init']):
            return 'Checkout Initiation'
        elif any(term in url_lower for term in ['shipping', 'delivery', 'address']):
            return 'Shipping/Address'
        elif any(term in url_lower for term in ['payment', 'pay', 'billing', 'paypal', 'stripe', 'credit']):
            return 'Payment Processing'
        elif any(term in url_lower for term in ['success', 'complete', 'confirmation', 'receipt', 'thank']):
            return 'Order Completion'
        elif any(term in url_lower for term in ['login', 'register', 'account', 'signup']):
            return 'Account/Authentication'
        elif 'checkout' in url_lower:
            return 'General Checkout'
        else:
            return 'Other E-commerce'

    def get_date_range(self):
        """Extract date range from log filenames"""
        dates = []
        for log_file in self.log_files:
            filename = os.path.basename(log_file)
            # Extract date from filename pattern like: something_20231215T1234Z_something.log
            date_match = re.search(r'_(\d{8})T\d{4}Z_', filename)
            if date_match:
                date_str = date_match.group(1)
                date_obj = datetime.strptime(date_str, '%Y%m%d')
                dates.append(date_obj)
        
        if dates:
            return min(dates), max(dates)
        return None, None

    def analyze_logs(self):
        """Main analysis function"""
        # Initialize data structures
        all_requests = []
        checkout_requests = []
        checkout_errors = []
        
        total_lines = 0
        parsed_lines = 0
        
        self.log("🔍 Processing log files...")
        self.log(f"Found {len(self.log_files)} log files to analyze")
        
        # Process all log files
        processed_files = 0
        for log_file in self.log_files:
            processed_files += 1
            # Show progress every 1000 files or for the last file
            if processed_files % 1000 == 0 or processed_files == len(self.log_files):
                self.log(f"Progress: {processed_files}/{len(self.log_files)} files processed...")
            
            with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
                for line_num, line in enumerate(f, 1):
                    total_lines += 1
                    log_entry = self.parse_log_line(line)
                    
                    if log_entry and log_entry.get('backend_status_code'):
                        parsed_lines += 1
                        all_requests.append(log_entry)
                        
                        # Extract URL from request
                        request_parts = log_entry['request'].split(' ')
                        if len(request_parts) >= 2:
                            url = request_parts[1].strip('"')
                            
                            # Check if checkout-related
                            if self.is_checkout_related(url):
                                log_entry['url'] = url
                                log_entry['checkout_stage'] = self.categorize_checkout_stage(url)
                                log_entry['pattern_category'] = self.get_pattern_category(url)
                                log_entry['is_bot'] = self.is_bot_traffic(log_entry['user_agent'])
                                log_entry['is_mobile'] = self.is_mobile_traffic(log_entry['user_agent'])
                                checkout_requests.append(log_entry)
                                
                                # Check if it's a server error (5xx only - focus on actionable errors)
                                status_code = log_entry['backend_status_code']
                                if status_code >= 500:
                                    checkout_errors.append(log_entry)
        
        self.log(f"📊 Processed {total_lines} log lines, parsed {parsed_lines} valid entries")
        self.log("")
        
        # Store data for analysis
        self.all_requests = all_requests
        self.checkout_requests = checkout_requests
        self.checkout_errors = checkout_errors
        
        # Run all analysis sections
        self.show_data_range()
        self.analyze_overall_summary()
        self.analyze_pattern_breakdown()
        self.analyze_daily_trends()
        self.analyze_hourly_patterns()
        self.analyze_user_agents()
        self.analyze_error_types()
        self.analyze_performance_correlation()

    def show_data_range(self):
        """Show date range analysis"""
        self.log("📅 DATA RANGE ANALYSIS:")
        self.log("=" * 50)
        
        first_date, last_date = self.get_date_range()
        if first_date and last_date:
            self.log(f"First day in data: {first_date.strftime('%Y-%m-%d')}")
            self.log(f"Last day in data: {last_date.strftime('%Y-%m-%d')}")
            duration = (last_date - first_date).days + 1
            self.log(f"Total days analyzed: {duration}")
        else:
            self.log("Could not determine date range from filenames")
        self.log("")

    def analyze_overall_summary(self):
        """Analyze overall checkout error summary"""
        self.log("📊 CHECKOUT ERROR SUMMARY:")
        self.log("=" * 50)
        
        total_requests = len(self.all_requests)
        total_checkout_requests = len(self.checkout_requests)
        total_checkout_errors = len(self.checkout_errors)
        
        if total_checkout_requests > 0:
            checkout_error_rate = (total_checkout_errors / total_checkout_requests) * 100
            checkout_traffic_pct = (total_checkout_requests / total_requests) * 100 if total_requests > 0 else 0
        else:
            checkout_error_rate = 0
            checkout_traffic_pct = 0
        
        self.log(f"Total requests: {total_requests:,}")
        self.log(f"Checkout-related requests: {total_checkout_requests:,} ({checkout_traffic_pct:.2f}% of all traffic)")
        self.log(f"Checkout errors (4xx + 5xx): {total_checkout_errors:,}")
        self.log(f"Checkout error rate: {checkout_error_rate:.2f}%")
        self.log("")
        
        # All errors are server errors (5xx) since we focus on actionable issues
        if total_checkout_errors > 0:
            self.log("Error breakdown:")
            self.log(f"  5xx Server Errors: {total_checkout_errors:,} (100.0%)")
            self.log("")
        
        # Top problematic URLs
        if self.checkout_errors:
            self.log("Top 10 problematic checkout URLs:")
            url_errors = Counter()
            for error in self.checkout_errors:
                # Clean URL (remove query params for grouping)
                clean_url = error['url'].split('?')[0]
                url_errors[clean_url] += 1
            
            for url, count in url_errors.most_common(10):
                self.log(f"  {count:>4} {url}")
            self.log("")

    def analyze_pattern_breakdown(self):
        """Analyze errors by checkout funnel stage"""
        self.log("🛒 CHECKOUT FUNNEL BREAKDOWN:")
        self.log("=" * 50)
        
        # Group by funnel stage
        funnel_stats = defaultdict(lambda: {'requests': 0, 'errors': 0, 'urls': defaultdict(int)})
        
        for request in self.checkout_requests:
            stage = request['pattern_category']
            funnel_stats[stage]['requests'] += 1
            
        for error in self.checkout_errors:
            stage = error['pattern_category']
            funnel_stats[stage]['errors'] += 1
            # Track top URLs for this stage
            clean_url = error['url'].split('?')[0]
            funnel_stats[stage]['urls'][clean_url] += 1
        
        # Sort by error count
        sorted_stages = sorted(funnel_stats.items(), key=lambda x: x[1]['errors'], reverse=True)
        
        self.log(f"{'Checkout Stage':<20} {'Requests':<12} {'Errors':<8} {'Error Rate':<12} {'Status'}")
        self.log("-" * 70)
        
        for stage, stats in sorted_stages:
            if stats['requests'] == 0:
                continue
                
            error_rate = (stats['errors'] / stats['requests'] * 100)
            
            # Status based on industry research - realistic e-commerce error rate thresholds
            if error_rate > 1.0:
                status = "🚨 CRITICAL"
            elif error_rate > 0.6:
                status = "⚠️  HIGH"
            elif error_rate > 0.3:
                status = "🔶 MEDIUM"
            else:
                status = "✅ GOOD"
            
            self.log(f"{stage:<20} {stats['requests']:<12,} {stats['errors']:<8} {error_rate:>6.2f}% {status}")
            
            # Show top problematic URLs for this stage (top 3)
            if stats['urls']:
                for url, count in sorted(stats['urls'].items(), key=lambda x: x[1], reverse=True)[:3]:
                    self.log(f"    {count:>4} {url}")
            self.log("")
        else:
            self.log("No checkout-related requests found")
        
        self.log("🔧 CHECKOUT PATTERNS USED:")
        self.log("Focusing on: " + ", ".join(self.checkout_patterns[:8]) + "...")
        self.log("")

    def analyze_daily_trends(self):
        """Analyze daily checkout error trends"""
        self.log("📈 DAILY CHECKOUT ERROR TRENDS:")
        self.log("=" * 50)
        
        # Group by date
        daily_stats = defaultdict(lambda: {'total': 0, 'checkout': 0, 'errors': 0})
        
        for request in self.all_requests:
            date_str = request['timestamp'][:10]  # YYYY-MM-DD
            daily_stats[date_str]['total'] += 1
        
        for request in self.checkout_requests:
            date_str = request['timestamp'][:10]
            daily_stats[date_str]['checkout'] += 1
        
        for error in self.checkout_errors:
            date_str = error['timestamp'][:10]
            daily_stats[date_str]['errors'] += 1
        
        # Sort by date and display
        sorted_dates = sorted(daily_stats.keys())
        
        self.log(f"{'Date':<12} {'Total Req':<10} {'Checkout':<10} {'Errors':<8} {'Error Rate':<10} {'Trend'}")
        self.log("-" * 65)
        
        prev_error_rate = None
        for date in sorted_dates:
            stats = daily_stats[date]
            error_rate = (stats['errors'] / stats['checkout'] * 100) if stats['checkout'] > 0 else 0
            
            # Trend indication
            trend = ""
            if prev_error_rate is not None:
                if error_rate > prev_error_rate + 0.5:
                    trend = "📈 WORSE"
                elif error_rate < prev_error_rate - 0.5:
                    trend = "📉 BETTER" 
                else:
                    trend = "➡️  STABLE"
            
            self.log(f"{date:<12} {stats['total']:<10,} {stats['checkout']:<10,} {stats['errors']:<8} {error_rate:>6.2f}%  {trend}")
            prev_error_rate = error_rate
        
        self.log("")

    def analyze_hourly_patterns(self):
        """Analyze hourly checkout error patterns"""
        self.log("🕐 HOURLY CHECKOUT ERROR PATTERNS:")
        self.log("=" * 50)
        
        # Group by hour
        hourly_stats = defaultdict(lambda: {'total': 0, 'checkout': 0, 'errors': 0})
        
        for request in self.all_requests:
            hour = request['timestamp'][11:13]  # Extract hour
            hourly_stats[hour]['total'] += 1
        
        for request in self.checkout_requests:
            hour = request['timestamp'][11:13]
            hourly_stats[hour]['checkout'] += 1
        
        for error in self.checkout_errors:
            hour = error['timestamp'][11:13]
            hourly_stats[hour]['errors'] += 1
        
        # Calculate averages and display
        total_days = len(set(r['timestamp'][:10] for r in self.all_requests))
        
        self.log(f"{'Hour':<6} {'Avg Req/Hr':<12} {'Avg Checkout':<12} {'Avg Errors':<11} {'Error Rate':<10} {'Status'}")
        self.log("-" * 70)
        
        for hour in sorted(hourly_stats.keys()):
            stats = hourly_stats[hour]
            avg_total = stats['total'] / total_days if total_days > 0 else 0
            avg_checkout = stats['checkout'] / total_days if total_days > 0 else 0
            avg_errors = stats['errors'] / total_days if total_days > 0 else 0
            error_rate = (stats['errors'] / stats['checkout'] * 100) if stats['checkout'] > 0 else 0
            
            # Status indication
            if error_rate > 5:
                status = "🚨 HIGH"
            elif error_rate > 2:
                status = "⚠️  MEDIUM"
            else:
                status = "✅ LOW"
            
            self.log(f"{hour}:00 {avg_total:<12.1f} {avg_checkout:<12.1f} {avg_errors:<11.1f} {error_rate:>7.2f}%  {status}")
        
        self.log("")

    def analyze_checkout_funnel(self):
        """Analyze checkout funnel error breakdown"""
        self.log("🛒 CHECKOUT FUNNEL ERROR BREAKDOWN:")
        self.log("=" * 50)
        
        # Group by checkout stage
        funnel_stats = defaultdict(lambda: {'requests': 0, 'errors': 0})
        
        for request in self.checkout_requests:
            stage = request['checkout_stage']
            funnel_stats[stage]['requests'] += 1
        
        for error in self.checkout_errors:
            stage = error['checkout_stage']
            funnel_stats[stage]['errors'] += 1
        
        # Sort by error count and display
        sorted_stages = sorted(funnel_stats.items(), key=lambda x: x[1]['errors'], reverse=True)
        
        self.log(f"{'Funnel Stage':<25} {'Requests':<10} {'Errors':<8} {'Error Rate':<10} {'Status'}")
        self.log("-" * 65)
        
        for stage, stats in sorted_stages:
            error_rate = (stats['errors'] / stats['requests'] * 100) if stats['requests'] > 0 else 0
            
            if error_rate > 5:
                status = "🚨 CRITICAL"
            elif error_rate > 2:
                status = "⚠️  HIGH"
            elif error_rate > 1:
                status = "🔶 MEDIUM"
            else:
                status = "✅ GOOD"
            
            self.log(f"{stage:<25} {stats['requests']:<10,} {stats['errors']:<8} {error_rate:<10.2f}% {status}")
        
        self.log("")

    def analyze_user_agents(self):
        """Analyze user agent and traffic source patterns"""
        self.log("🤖 USER AGENT & TRAFFIC SOURCE ANALYSIS:")
        self.log("=" * 50)
        
        # Bot detection explanation with actual detected bots
        self.log("🔍 Bot Detection Methodology:")
        self.log("Bots are identified by user agent strings containing keywords like:")
        self.log("bot, crawler, spider, scraper, googlebot, bingbot, curl, wget, python, etc.")
        self.log("")
        
        # Show actual bot user agents found in the data
        if self.checkout_errors:
            bot_user_agents = set()
            for error in self.checkout_errors:
                if error['is_bot']:
                    # Truncate very long user agents for readability
                    ua = error['user_agent']
                    if len(ua) > 180:
                        ua = ua[:180] + "..."
                    bot_user_agents.add(ua)
            
            if bot_user_agents:
                self.log("🤖 Actual Bot User Agents Found in Checkout Errors:")
                for ua in sorted(list(bot_user_agents)[:10]):  # Show top 10
                    self.log(f"  • {ua}")
                if len(bot_user_agents) > 10:
                    self.log(f"  ... and {len(bot_user_agents) - 10} more bot types")
                self.log("")
        
        # Bot vs Human analysis
        bot_errors = len([e for e in self.checkout_errors if e['is_bot']])
        human_errors = len([e for e in self.checkout_errors if not e['is_bot']])
        total_errors = len(self.checkout_errors)
        
        bot_requests = len([r for r in self.checkout_requests if r['is_bot']])
        human_requests = len([r for r in self.checkout_requests if not r['is_bot']])
        
        self.log("Bot vs Human Traffic Analysis:")
        if bot_requests > 0:
            bot_error_rate = (bot_errors / bot_requests) * 100
            bot_error_pct = (bot_errors / total_errors * 100) if total_errors > 0 else 0
            self.log(f"  Bot Traffic: {bot_requests:,} requests, {bot_errors:,} errors ({bot_error_rate:.2f}% error rate, {bot_error_pct:.1f}% of all errors)")
        else:
            self.log(f"  Bot Traffic: 0 requests")
            
        if human_requests > 0:
            human_error_rate = (human_errors / human_requests) * 100
            human_error_pct = (human_errors / total_errors * 100) if total_errors > 0 else 0
            self.log(f"  Human Traffic: {human_requests:,} requests, {human_errors:,} errors ({human_error_rate:.2f}% error rate, {human_error_pct:.1f}% of all errors)")
        else:
            self.log(f"  Human Traffic: 0 requests")
        self.log("")
        
        # Mobile vs Desktop analysis
        mobile_errors = len([e for e in self.checkout_errors if e['is_mobile']])
        desktop_errors = len([e for e in self.checkout_errors if not e['is_mobile']])
        
        mobile_requests = len([r for r in self.checkout_requests if r['is_mobile']])
        desktop_requests = len([r for r in self.checkout_requests if not r['is_mobile']])
        
        self.log("Mobile vs Desktop Analysis:")
        if mobile_requests > 0:
            mobile_error_rate = (mobile_errors / mobile_requests) * 100
            self.log(f"  Mobile Traffic: {mobile_requests:,} requests, {mobile_errors:,} errors ({mobile_error_rate:.2f}% error rate)")
        else:
            self.log(f"  Mobile Traffic: 0 requests")
            
        if desktop_requests > 0:
            desktop_error_rate = (desktop_errors / desktop_requests) * 100
            self.log(f"  Desktop Traffic: {desktop_requests:,} requests, {desktop_errors:,} errors ({desktop_error_rate:.2f}% error rate)")
        else:
            self.log(f"  Desktop Traffic: 0 requests")
        self.log("")
        
        # Top user agents causing errors
        if self.checkout_errors:
            self.log("Top 10 User Agents Causing Checkout Errors:")
            user_agent_errors = Counter()
            for error in self.checkout_errors:
                # Clean up user agent string (first 80 chars)
                ua = error['user_agent'][:80] + "..." if len(error['user_agent']) > 80 else error['user_agent']
                user_agent_errors[ua] += 1
            
            for ua, count in user_agent_errors.most_common(10):
                bot_indicator = "🤖" if self.bot_regex.search(ua) else "👤"
                self.log(f"  {count:>3} {bot_indicator} {ua}")
            self.log("")

    def analyze_error_types(self):
        """Analyze specific error types and codes"""
        self.log("🚨 CHECKOUT ERROR TYPE ANALYSIS:")
        self.log("=" * 50)
        
        # Error code descriptions
        error_descriptions = {
            400: "Bad Request - Invalid request syntax",
            401: "Unauthorized - Authentication required", 
            403: "Forbidden - Access denied",
            404: "Not Found - Resource not found",
            405: "Method Not Allowed - HTTP method not supported",
            408: "Request Timeout - Client took too long",
            409: "Conflict - Resource conflict",
            422: "Unprocessable Entity - Invalid request data",
            429: "Too Many Requests - Rate limit exceeded",
            500: "Internal Server Error - Server-side error",
            502: "Bad Gateway - Upstream server error", 
            503: "Service Unavailable - Server overloaded",
            504: "Gateway Timeout - Upstream timeout",
            505: "HTTP Version Not Supported"
        }
        
        # Count errors by status code
        status_code_errors = Counter()
        for error in self.checkout_errors:
            status_code_errors[error['backend_status_code']] += 1
        
        # Only analyze 5xx server errors (actionable by the business)
        if status_code_errors:
            self.log("5xx Server Errors (backend/infrastructure issues):")
            for code in sorted(status_code_errors.keys()):
                count = status_code_errors[code]
                description = error_descriptions.get(code, "Unknown error")
                self.log(f"  {code}: {count:,} errors - {description}")
            self.log("")
        
        # Error codes by checkout stage
        if self.checkout_errors:
            self.log("Error codes by checkout funnel stage:")
            stage_errors = defaultdict(lambda: defaultdict(int))
            
            for error in self.checkout_errors:
                stage = error['checkout_stage']
                code = error['backend_status_code']
                stage_errors[stage][code] += 1
            
            for stage in sorted(stage_errors.keys()):
                self.log(f"  {stage}:")
                for code in sorted(stage_errors[stage].keys()):
                    count = stage_errors[stage][code]
                    self.log(f"    {code}: {count:,} errors")
            self.log("")

    def analyze_performance_correlation(self):
        """Analyze performance correlation with errors"""
        self.log("⏱️  CHECKOUT PERFORMANCE CORRELATION:")
        self.log("=" * 50)
        
        if not self.checkout_requests:
            self.log("No checkout requests to analyze")
            self.log("")
            return
        
        # Calculate average response times
        successful_requests = [r for r in self.checkout_requests if r['backend_status_code'] < 400]
        error_requests = self.checkout_errors
        
        if successful_requests:
            success_times = []
            for req in successful_requests:
                total_time = (req['request_processing_time'] + 
                            req['backend_processing_time'] + 
                            req['response_processing_time'])
                if total_time > 0:  # Only include valid times
                    success_times.append(total_time)
            
            if success_times:
                avg_success_time = sum(success_times) / len(success_times)
                max_success_time = max(success_times)
                self.log(f"Successful checkout requests:")
                self.log(f"  Average response time: {avg_success_time:.3f} seconds")
                self.log(f"  Maximum response time: {max_success_time:.3f} seconds")
                self.log(f"  Total successful requests: {len(successful_requests):,}")
            else:
                self.log("No valid response times found for successful requests")
        
        if error_requests:
            error_times = []
            for req in error_requests:
                total_time = (req['request_processing_time'] + 
                            req['backend_processing_time'] + 
                            req['response_processing_time'])
                if total_time > 0:  # Only include valid times
                    error_times.append(total_time)
            
            if error_times:
                avg_error_time = sum(error_times) / len(error_times)
                max_error_time = max(error_times)
                self.log(f"Checkout error requests:")
                self.log(f"  Average response time: {avg_error_time:.3f} seconds")
                self.log(f"  Maximum response time: {max_error_time:.3f} seconds")
                self.log(f"  Total error requests: {len(error_requests):,}")
                
                # Compare success vs error times
                if successful_requests and success_times and error_times:
                    if avg_error_time > avg_success_time:
                        diff = avg_error_time - avg_success_time
                        self.log(f"  ⚠️  Error requests are {diff:.3f} seconds slower on average")
                    else:
                        self.log(f"  ✅ Error requests are not significantly slower")
            else:
                self.log("No valid response times found for error requests")
        
        # Timeout analysis
        if self.checkout_requests:
            slow_requests = [r for r in self.checkout_requests 
                           if (r['request_processing_time'] + r['backend_processing_time'] + 
                               r['response_processing_time']) > 10]  # > 10 seconds
            
            if slow_requests:
                self.log(f"Slow checkout requests (>10 seconds): {len(slow_requests):,}")
                slow_errors = [r for r in slow_requests if r['backend_status_code'] >= 400]
                if slow_errors:
                    slow_error_rate = (len(slow_errors) / len(slow_requests)) * 100
                    self.log(f"  Slow requests with errors: {len(slow_errors):,} ({slow_error_rate:.1f}%)")
        
        self.log("")



    def run(self):
        """Run the complete analysis"""
        try:
            # Clear output file if it exists
            if self.output_file:
                with open(self.output_file, 'w') as f:
                    f.write("")  # Clear file
            
            self.log("🛒 E-Commerce Checkout & Cart Error Analysis")
            self.log("=" * 60)
            self.log(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            self.log(f"Log directory: {self.log_dir}")
            if self.output_file:
                self.log(f"Output file: {self.output_file}")
            self.log("")
            
            self.validate_log_directory()
            self.analyze_logs()
            
            self.log("Analysis complete! 🎉")
            
        except Exception as e:
            self.log(f"❌ Error during analysis: {str(e)}")
            sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description='E-Commerce Checkout & Cart Error Analysis for ELB Logs',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 ecommerce_checkout_analysis.py
  python3 ecommerce_checkout_analysis.py elb-logs
  python3 ecommerce_checkout_analysis.py elb-logs --output analysis_results.txt
  python3 ecommerce_checkout_analysis.py __elb-logs --output /tmp/checkout_analysis.log
        """
    )
    
    parser.add_argument(
        'log_directory',
        nargs='?',
        default='elb-logs',
        help='Directory containing ELB log files (default: elb-logs)'
    )
    
    parser.add_argument(
        '--output', '-o',
        help='Output file to save analysis results (in addition to stdout)'
    )
    
    args = parser.parse_args()
    
    analyzer = CheckoutAnalyzer(args.log_directory, args.output)
    analyzer.run()


if __name__ == '__main__':
    main() 