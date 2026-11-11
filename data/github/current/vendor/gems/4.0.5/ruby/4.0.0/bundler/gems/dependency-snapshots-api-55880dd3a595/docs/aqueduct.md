# Aqueduct integration

This service can enqueue and process Aqueduct jobs in production/proxima environments. GHES remains disabled.

## Configuration

Set the following env vars (production/proxima overlays already provide the non-secret ones):

- `AQUEDUCT_ENABLED=true`
- `AQUEDUCT_URL` – gateway URL (production uses `https://aqueduct-gateway-production.service.iad.github.net`, proxima uses `http://api.aqueduct-gateway-<stamp>.svc.cluster.local`).
- `AQUEDUCT_APP_NAME` – publishing app name, defaults to `dependency-snapshots-api`.
- `AQUEDUCT_ECHO_QUEUE` – queue for the echo worker, defaults to `dsapi.echo`.
- `AQUEDUCT_API_KEY` / `AQUEDUCT_API_KEY_VERSION` – provided via Vault/secrets-federation.

Aqueduct is only considered enabled when the flag is true, the URL/app/key are present, the environment is `production` or `proxima`, and `ENTERPRISE` is `false` (GHES sets it to `true`).

## Worker

A dedicated worker binary is built into the image: `./bin/ds-aqueduct-worker`.

- **Run locally**: `go run ./cmd/aqueduct-worker`
- The worker uses the configured echo queue and logs each payload.
- Stats are reported under the `aqueduct.worker` prefix via the existing stats client.

## Sending a test job

The same binary can enqueue a test echo job without running the worker:

```bash
AQUEDUCT_ENABLED=true AQUEDUCT_URL=<gateway> AQUEDUCT_API_KEY=<key> AQUEDUCT_API_KEY_VERSION=<version> \
AQUEDUCT_APP_NAME=dependency-snapshots-api AQUEDUCT_ECHO_QUEUE=dsapi.echo \
  go run ./cmd/aqueduct-worker --mode send-echo --message "hello aqueduct"
```

This produces an echo job that the worker will consume from `AQUEDUCT_ECHO_QUEUE`.

## Local development (aqueduct-lite)

We now run a lightweight Aqueduct locally via docker compose:

```bash
# start azurite + mysql + redis + aqueduct-lite
script/start-containers

# in another shell, point the worker/client at the local gateway
export APP_ENV=production \
  AQUEDUCT_ENABLED=true \
  AQUEDUCT_URL=http://127.0.0.1:18081 \
  AQUEDUCT_APP_NAME=dependency-snapshots-api \
  AQUEDUCT_ECHO_QUEUE=dsapi_echo \
  AQUEDUCT_API_KEY=devkey \
  AQUEDUCT_API_KEY_VERSION=0

# run the worker
go run ./cmd/aqueduct-worker --mode worker

# in a second terminal, send a job
go run ./cmd/aqueduct-worker --mode send-echo --message "hello local aqueduct"
```

Notes:
- Queue names must match `[A-Za-z0-9_-]`; use `dsapi_echo` (no dots).
- `AQUEDUCT_API_KEY`/version can be any non-empty values with aqueduct-lite.
- `APP_ENV` must be `production` or `proxima` and `ENTERPRISE` must be unset/`false` to satisfy `AqueductConfigured()`.

## Kubernetes

- A new deployment `aqueduct-worker` is part of the base kustomize configuration.
- Production and proxima overlays enable Aqueduct and set gateway URLs/queue names.
- The worker shares the same `environment` ConfigMap and `vault-secrets` secret as the API.
