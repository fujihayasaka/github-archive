# Splunk

Helpful Queries for Trust-Metadata-API Splunk

## Environments

The `kube_namespace` matches the Proxima stamp. For example, `trust-metadata-api-production` is the namespace for the Trust-Metadata-API in the production environment and `trust-metadata-api-prod-weu-01` is the namespace for the Trust-Metadata-API in the West EU environment.

See the main [playbook](../playbook.md#stamps) for a list of environments/Proxima Stamps.

There are currently two different Splunk instance which can be accessed via [Okta](https://github.okta.com/).

- [Splunk](https://splunk.githubapp.com/en-US/app/gh_reference_app/search)
- [Splunk EU](https://splunk-eu.githubapp.com/en-US/app/gh_reference_app/search)

## Useful Queries

> For more Splunk queries, see the [The Hub - Splunk Cookbook](https://thehub.github.com/epd/engineering/dev-practicals/performance/tools/splunk/).

### Search for errors in Trust-Metadata-API

```text
index IN(trust-metadata) kube_namespace="trust-metadata-api-production"| spath SeverityText | search SeverityText=ERROR
```

### Search for a Request ID

Search for a Request by ID in TMA & Rails:

```text
index IN(trust-metadata, rails) gh.request_id="90C1:368EF6:B870614:BB8B521:675B3BC3"
```

The TMA and Rails log Request ID as `gh.request_id` and the GLB log Request ID as `request_id`. This query will search for a Request ID in all three logs:

```text
index IN(trust-metadata, rails, glb) (gh.request_id="90C1:368EF6:B870614:BB8B521:675B3BC3" OR request_id="90C1:368EF6:B870614:BB8B521:675B3BC3")
```

### Search Rails Logs for Trust-Metadata-API

Search the Rails logs only for the `github/trust_metadata` catalog service:

```text
index=rails catalog_service=github/trust_metadata
```

### Search by Rails Controller

Rails Attestation Web View:

```text
index=rails catalog_service=github/trust_metadata controller=RepositoryAttestationsController
```

Rails Attestation API:

```text
index=rails catalog_service=github/trust_metadata "code.namespace"="Api::Attestations"
```
