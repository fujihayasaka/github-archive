#!/bin/sh
# Payloads sent via JSON must be base64 encoded.

# Want to see this work locally? Make sure redis is running (brew install redis)
# Start up aqueduct-lite (clone into your go path and script/server)
# Startup the worker script (`AQUEDUCT_URL="http://127.0.0.1:8085/twirp" ruby ./script/aqueduct-worker`)
# Run this script and see it execute sync_vulnerabilities.
PAYLOAD=$(echo "{\"job_class\":\"SyncVulnerabilitiesJob\", \"job_id\":\"1a7934a4-a26f-474c-b94b-3894bd31b743\", \"queue_name\":\"service-to-service\", \"arguments\":[] }" | base64 -w0)

curl --verbose --header "Content-Type:application/json" --data "{\"app\": \"dependency-graph-api\", \"queue\":\"service-to-service\", \"payload\":\"$PAYLOAD\"}" "$AQUEDUCT_URL/aqueduct.api.v1.JobQueueService/Send"
