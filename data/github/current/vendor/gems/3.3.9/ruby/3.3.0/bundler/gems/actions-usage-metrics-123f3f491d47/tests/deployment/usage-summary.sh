#!/bin/bash
# This testing script is meant to be run in the CI/CD pipeline.
# It requires the following environment variables to be set:
#
# - AUM_URL: The URL of the Actions Usage Metrics in environment to test
# - ORG_ID: The organization ID of the organization to test with

set -e

# Get the current usage summary
echo "Getting the current usage summary..."
usage_summary_current=$(script/hmac-curl -s -X POST https://$AUM_URL/twirp/actions_usage_metrics.api.v1.UsageApi/GetUsageSummary -H "Content-Type: application/json" -d "{\"request_options\": {\"date_range\": \"DATE_RANGE_TYPE_LATEST_MONTH\", \"scope\":{\"owner_id\": $ORG_ID, \"scope_type\": \"SCOPE_TYPE_ORG\"} }}")
total_minutes_current=$(echo $usage_summary_current | jq '.total_minutes | tonumber')
job_executions_current=$(echo $usage_summary_current | jq '.job_executions | tonumber')
echo "Current usage summary: total_minutes_current=$total_minutes_current, job_executions_current=$job_executions_current"

# Assert that some data is returned
echo -e "\nAsserting that total_minutes_current > 0..."
if [ $total_minutes_current -gt 0 ]; then
    echo "$total_minutes_current > 0: pass"
else
    echo "$total_minutes_current <= 0: fail"
    exit 1
fi

echo -e "\nAsserting that job_executions_current > 0..."
if [ $job_executions_current -gt 0 ]; then
    echo "$job_executions_current > 0: pass"
else
    echo "$job_executions_current <= 0: fail"
    exit 1
fi

echo -e "\nDone."
