# Decoding Event Payloads

Event payloads are stored in the `payloads` table for 30 days to support re-runs. These payloads can be retrieved and decompressed to help debug customer issues.

>**Note**
>Payloads can also be retrieved from Aqueduct telemetry, see
[Basic Investigation Playbook: Webhook payloads](https://github.com/github/ops/blob/master/docs/playbooks/actions/basic-investigation-playbook.md#get-webhook-payload-from-warehouse)
for details.

## Pre-requisites

Since the payloads table is not stored in the data warehouse, access to a production shell is required.

* Datadot - entitlements via https://github.com/github/entitlements/blob/master/ldap/apps/okta-network-gateway/data.txt
* Production Shell - https://thehub.github.com/security/security-operations/production-shell-access/

## Obtain the workflow build ID

With the workflow run ID, query the `workflow_builds` table for the primary `id`.

This can optionally be done from Datadot (https://data.githubapp.com/warehouse/hive/snapshots_presto/workflow_builds), but we'll need to connect to a production shell afterwards to query the `payloads` table.

From a production shell, connect to the Launch analytics cluster:
```shell
gh-dbconsole launch-analytics launch
```

In the MySQL prompt, query the `workflow_builds` table with the workflow run ID:
```sql
SELECT id FROM workflow_builds WHERE workflow_run_id = 1234 LIMIT 1;
```

## Query the payloads table for the compressed payload

The payload is stored as a `mediumblob` and compressed with [snappy](https://github.com/golang/snappy).

From a production shell, connect to the payloads analytics cluster:
```shell
gh-dbconsole actions-workflow-payloads-analytics actions_workflow_payloads
```

In the MySQL prompt, query the payloads table for the `body`:
```sql
SELECT id, TO_BASE64(body) FROM payloads WHERE workflow_build_id = 1185759252 LIMIT 1;
```

Copy the base64 encoded body into a file.

## Decode and decompress the payload

> **Warning**
> This payload could contain private user information, so don't share it publicly.

You can decode the payload using https://deserializerv2.azurewebsites.net/ or follow the instructions
below for decoding locally on your machine.

Decode the base64 payload:

```shell
base64 --decode -i payload.b64 -o payload.bytes
```

Use the following Go program to decompress the payload body with `snappy`.

```shell
go mod init payloads
go get "github.com/golang/snappy"
touch main.go
```

And then add the following to `main.go`:
```go
package main

import (
	"fmt"
	"os"

	"github.com/golang/snappy"
)

func main() {
	body, err := os.ReadFile("./payload.bytes")
	if err != nil {
		panic(err)
	}

	decoded, err := snappy.Decode(nil, body)
	if err != nil {
		panic(err)
	}

	fmt.Println(string(decoded))
}
```

Run the Go program:
```shell
go run main.go
```

This program will output the full JSON payload.
