# Hydro

Hydro is an event logging system which Github uses. Learn more about it here: [hydro](https://thehub.github.com/epd/engineering/products-and-services/internal/hydro/)

## Setting hydro schema 

The schema is defined in hydro-schemas repo: https://github.com/github/hydro-schemas/blob/main/proto/hydro/schemas/github/trust_metadata_api/v0/create_attestation.proto

To change the schema, we need to change the file in the hydro-schemas repo and submit the PR to merge and deploy the new schema. After merging the schema, we need to generate schema for TMA. 

Make sure you have cloned a local copy of github/hydro-schemas before proceeding

Execute the following in hydro-schemas to generate a new schema in TMA 
```
script/generate \
  --go-out $YOUR_PATH_TO_TMA/trust-metadata-api \
  --go-prefix github.com/github/trust-metadata-api \
  --protoc-gen-go google.golang.org/protobuf/cmd/protoc-gen-go@v1.30.0 \
  proto/hydro/schemas/github/trust_metadata_api
```

## Local Development

When you create an attestation in local development you should see a message logging in the terminal

example:
```
http.target=/twirp/github.trust_metadata_api.GitHubAPI/CreateAttestationByOwnerRepository gh.request_id=7107fe60-22b8-4100-a466-2b5549afc868 http.status_code=200
2024/01/18 03:06:26 sink.go:115: topic="github.trust_metadata_api.v0.CreateAttestation" value={"owner_id":"2", "repository_id":"1", "workflow_run_id":"3024091546"}
```


# Hydro metrics for CreateAttestation 

Here is the datadog dashboard for monitoring the hydro message
https://app.datadoghq.com/dashboard/tuk-8d8-4qu/hydrotopic?refresh_mode=sliding&tpl_var_cluster=potomac&tpl_var_kafka_cluster=potomac&tpl_var_topic=github.trust_metadata_api.v0.createattestation&view=spans&from_ts=1705605545044&to_ts=1705609145044&live=true

## Resources 
- Here is the doc for the go client: https://thehub.github.com/epd/engineering/products-and-services/internal/hydro/installation/golang/
- Here is the hydro UI: https://hydro.githubapp.com/kafka/clusters/potomac/topic?topic=github.trust_metadata_api.v0.CreateAttestation
- Here is the hydro-client-go repo: https://github.com/github/hydro-client-go
- Here is the hydro-schemas repo: https://github.com/github/hydro-schemas



