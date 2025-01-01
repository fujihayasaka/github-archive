# trust-metadata-api

API for handling artifact signing metadata

- [Moda Dashboard](https://moda.githubapp.com/apps/trust-metadata-api)
- [Datadog Dashboard](https://app.datadoghq.com/dashboard/p5b-5gt-v76/trust-metadata-api)
- [Datadog Tracer](https://app.datadoghq.com/apm/services/trust-metadata-api/operations/github_com_github_trust_metadata_api_o_11_y.internal)
- [Sentry - TMA](https://sentry.io/organizations/github/projects/trust-metadata-api/?project=4504079440740352)
- [Sentry - github/trust_metadata (dotcom)](https://github.sentry.io/issues/?query=cause_catalog_service%3Agithub%2Ftrust_metadata&referrer=issue-list&statsPeriod=14d)
- [Splunk](<https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%20IN(trust-metadata)%20kube_namespace%3Dtrust-metadata-api-*%20&earliest=-15m&latest=now>)

## Endpoints

| Environment | Public Service URL                               |
|-------------|--------------------------------------------------|
| Staging     | https://trust-metadata-api-staging.githubapp.com |
| Production  | https://trust-metadata-api.githubapp.com         |
| Proxima     | No public endpoints exposed                      |

## Development Setup

### Initial setup

```shell
# Install golang-migrate and other tools
brew bundle
```

### Running locally

```shell
# Start MySQL dev and Azure blob storage containers and run migrations
make dev-start
make dev-migrate-up
# Add test data to the local data store
# Identifiers needed to fetch these attestations will be printed to the terminal
make dev-populate-db
# Build TMA binary and start the server locally
make dev-server
# Use the poller tool to create more attestations or fetch existing ones
go run ./scripts/poller/dotcom.go <flags here>
```

To make a request against the local server, use [script/body-hmac-request.go](script/body-hmac-request.go).

The HMAC keys used with the local deployment can be found in [config/development.yaml](config/development.yaml). Each Twirp service expects a specific Client ID header and HMAC key.

### Example Usage - NPM Use Case

Post to TMA using purl with hmac key(npm usecase):

```shell
bundle=$(<test/data/sigstore.js-3.0.0.bundle.json)

go run script/body-hmac-request.go -request-url "http://localhost:8337/twirp/github.trust_metadata_api.PackageInfoWriteAPI/CreatePackageAttestation" -request-body '{"purl": "pkg:npm/sigstore@2.2.0", "bundle":'"$bundle"'}'  -request-client-name "uploading-worker" -hmac-key "mysecretkey"
```

Retrieve package attestations by purl from API with hmac key(npm usecase):

```shell
go run script/body-hmac-request.go -request-body '{"purl": "pkg:npm/sigstore@2.2.0"}' -request-url 'http://localhost:8337/twirp/github.trust_metadata_api.PackageInfoReadAPI/GetPackageAttestations' -request-client-name "npm/read" -hmac-key "anothersecretkey"
```

Retrieve provenance from API with hmac key(npm usecase):

```shell
go run script/body-hmac-request.go -request-body '{"purl": "pkg:npm/sigstore@2.2.0"}' -request-url 'http://localhost:8337/twirp/github.trust_metadata_api.PackageInfoReadAPI/GetPackageProvenanceSummary' -request-client-name "npm/read" -hmac-key "anothersecretkey"
```

### Example Usage - Dotcom Use Case

Post to TMA using repoId, and ownerId with hmac key(dotcom usecase):

```shell
bundle=$(<test/data/sigstore.js-3.0.0.bundle.json)

go run script/body-hmac-request.go -request-url "http://localhost:8337/twirp/github.trust_metadata_api.GitHubAPI/CreateAttestationByOwnerRepository" -request-body '{"bundle":'"$bundle"',"repository_id": "1", "owner_id": "1"}'  -request-client-name "dotcom" -hmac-key "dotcomsecretkey"
```

Retrieve attestations by subjectDigest, repoId, and ownerId from API with hmac key(dotcom usecase):

```shell
go run script/body-hmac-request.go -request-body '{"subject_digest": "sha512:7dc53d7251f012cb36fccff5d4514cf09c1ce0f8c181b857a0db24a0ae60ba82b4a8640149e51b419449f81d9f0c522f8727f482a09a3eb7a5f66b336e1031ba", "repository_id": "1", "owner_id": "1", "per_page":"3"}' -request-url 'http://localhost:8337/twirp/github.trust_metadata_api.GitHubAPI/ListAttestationsBySubjectDigest' -request-client-name "dotcom" -hmac-key "dotcomsecretkey"
```

List attestation summaries by repoId, and ownerId from API with hmac key(dotcom usecase):

```shell
go run script/body-hmac-request.go -request-body '{"repository_id": "1", "owner_id": "1", "per_page":"3"}' -request-url 'http://localhost:8337/twirp/github.trust_metadata_api.GitHubAPI/ListAttestationSummariesByRepository' -request-client-name "dotcom" -hmac-key "dotcomsecretkey"
```

Retrieve an attestation by attestationId, repoId, and ownerId from API with hmac key(dotcom usecase):

```shell
go run script/body-hmac-request.go -request-body '{"attestation_id": "1", "repository_id": "1", "owner_id": "1", "per_page":"3"}' -request-url 'http://localhost:8337/twirp/github.trust_metadata_api.GitHubAPI/GetAttestationByRepository' -request-client-name "dotcom" -hmac-key "dotcomsecretkey"
```

Show Attestation:

```shell
go run script/body-hmac-request.go -request-body '{"attestation_id": "1", "repository_id": "1", "owner_id": "1", "per_page":"3"}' -request-url 'http://localhost:8337/twirp/github.trust_metadata_api.GitHubAPI/GetAttestationSummaryByRepository' -request-client-name "dotcom" -hmac-key "dotcomsecretkey" | jq
```

### Running tests

```shell
# Start MySQL dev and Azure blob storage containers and run migrations
make dev-start && make dev-migrate-up

# Run tests
make lint && make test
```

### Cleaning up local development

```shell
# Stop MySQL dev container
make dev-stop

# If you want to reset the database
make dev-clean
```

## Inter-service communication

Github services generally use [Twirp](https://twitchtv.github.io/twirp/docs/intro.html) as the inter-service communication protocol.

See [Twirp doc](./docs/protobuf-twirp.md) for more information.

## Go Dependencies

See [goproxy](https://github.com/github/goproxy/blob/main/doc/user.md) for details on how private dependencies work.

## Codespaces

This repo contains a custom devcontainer for Codespaces which sets up MariaDB and runs migrations. In order to resolve private dependencies with `goproxy`, you'll need to add a PAT to your Codespaces secrets:

1. Generate a legacy PAT [in your developer settings](https://github.com/settings/tokens).
1. Give it the `repo` scope.
1. Configure SSO with the `github` org.
1. Create a new Codespaces secret [in your Codespaces settings](https://github.com/settings/codespaces).
1. Give it a name of `CODESPACES_GITHUB_TOKEN` and a value containing the PAT created above.

## Deployment

The TMA is deployed to the following environments:
- Dotcom staging
- Dotcom production
- Proxima staff-wus2-01
- Proxima prod-weu-01

The service is deployed using [Heaven pipelines](https://devportal.githubapp.com/devportal/apps/trust-metadata-api?tab=deploysAndPipelines) and [merge queues](https://github.com/github/trust-metadata-api/queue). This allows us to easily deploy the TMA to all production
environments without having to invoke chatops individually for each one.

Once the a pull request is added to the merge queue, the pipeline will
automatically begin.

Deployment health can be checked [here](https://devportal.githubapp.com/devportal/apps/trust-metadata-api).

### Manual deployment with chatops

You can deploy to the `staging` and `staff-wus2-01` environments with chatops
in [`#package-security-ops`](https://github.slack.com/archives/C037TJZGCGN) for
testing purposes.

For example:
```shell
# deploy main
.deploy trust-metadata-api to <staging|staff-wus2-01|>

# deploy a Pull Request/branch
.deploy https://github.com/github/trust-metadata-api/pull/1234 to staging
```

If you need to deploy to a production environment
without a pipeline, use the `--ignore-required-pipeline` option:
`.deploy trust-metadata-api to production --ignore-required-pipeline`.

See [here](https://thehub.github.com/epd/engineering/devops/deployment/onboarding-to-heaven-pipelines/#normal-moda-app-that-uses-deploymentyaml) for
more information.

Sensitive environment variables, such as MySQL credentials, are stored securely in [Vault](./docs/vault.md). For a list of required environment variables, reference the `.envrc.example` file.

### Deploying Changes

To deploy `main` branch run the following command in [`#package-security-ops`](https://github.slack.com/archives/C037TJZGCGN):

```shell
.deploy trust-metadata-api to <staging|prod|staff-wus2-01>
```

## Managing Kubernetes Resources

Kubernetes resources are managed with Kustomize in the [config](./config/) directory.
The `gh` CLI tool has a [kustomize extension](https://github.com/github/gh-kustomize/tree/main) for generating Kubernetes resources from Kustomzie for the the Moda environment. This includes generating manifests into directories that are recognized by Moda.

Building new Kubernetes manifests can be done with `gh kustomize build`. More
information around commands can be found [here](https://github.com/github/gh-kustomize/tree/main).
