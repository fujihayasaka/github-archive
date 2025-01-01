#!/bin/bash
# This testing script is meant to be run in the CI/CD pipeline.
# It requires the following environment variables to be set:
#
# - AUM_URL: The URL of the Actions Usage Metrics in environment to test
# - ORG_ID: The organization ID of the organization to test with
# - AUM_GET_LIMIT: The limit of the number of items to get from the AUM API
# - REPOSITORY_ID: The repository ID of the repository to test with
# - WORKFLOW_FILE_PATH: The workflow file path of the workflow to test with

set -e

# Get the current usage summary
echo "Getting the current job usage..."
all_jobs_current=$(script/hmac-curl -s -X POST https://$AUM_URL/twirp/actions_usage_metrics.api.v1.UsageApi/GetJobUsage -H "Content-Type: application/json" -d "{\"request_options\": {\"date_range\": \"DATE_RANGE_TYPE_LATEST_MONTH\", \"scope\":{\"owner_id\": $ORG_ID, \"scope_type\": \"SCOPE_TYPE_ORG\"}, \"offset\": 0, \"limit\": $AUM_GET_LIMIT }}")
aum_test_job_current=$(echo $all_jobs_current | jq -c ".items[] | select( (.repository_id == \"$REPOSITORY_ID\") and .workflow_file_path == \"$WORKFLOW_FILE_PATH\" )")
total_minutes_current=$(echo $aum_test_job_current | jq '.total_minutes | tonumber')
job_executions_current=$(echo $aum_test_job_current | jq '.job_executions | tonumber')
echo "Current job usage: total_minutes_current=$total_minutes_current, job_executions_current=$job_executions_current"

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
