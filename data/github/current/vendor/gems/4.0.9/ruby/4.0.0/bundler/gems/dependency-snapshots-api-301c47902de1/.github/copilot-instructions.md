# Copilot Instructions for dependency-snapshots-api

## 🔖 Glossary
- Use `docs/glossary.md` for canonical definitions (snapshot, manifest, dependency, canonical snapshot).
- See `docs/README.md` for other developer docs (database, dataflows, service overview, Azure, enterprise).

## 🌍 Environments
**Cloud**
- Snapshot blobs stored in Azure Blob Storage (Azurite locally).
- Snapshots retained indefinitely.

**GHES**
- Snapshot blobs stored in the database.
- Historical snapshots and snapshots for non-default branches are discarded immediately.
- Feature flags are not available.

> Tests and features must respect these differences.

## 🚩 Feature flags
- **Policy:** Gate any change beyond a simple bug fix behind a feature flag.
- **Implementation:** See `internal/features` (Twirp Features API client).
- **Availability:** Cloud only; GHES must work safely with flags disabled.
- **Fallbacks:** Default to safe behavior when flags are absent; document in PR.
- **Cleanup:** Remove flags once stable and no longer need a toggle.

## 🧪 Testing

### Philosophy
- Red–green–refactor: create a failing test first and watch it fail.
- Favor unit tests; integration tests live in `test/integration_test.go` (no mocks/spies).
- Keep tests readable (helpers, descriptive names, custom failure messages).

### Commands

| Purpose | Command | Notes |
| --- | --- | --- |
| Unit tests | `make test-unit` | Starts containers; resets DB; `DEPENDENCY_SNAPSHOTS_DB=dependency_snapshots_test` |
| Integration (Cloud) | `make test-integration` | Requires Docker + Overmind; `ENABLE_AZURE_STORAGE_FOR_SNAPSHOT_BLOBS=1`; service on `http://localhost:9597` |
| Integration (GHES) | `make test-integration-enterprise` | Sets `ENTERPRISE=true` |
| Full suite | `make test` | Unit + both integration targets |
| Lint | `make lint` | Runs pre-commit (gofmt + golangci-lint) |
| Lint + tests | `script/test` | Convenience wrapper |

**Prereqs:** Docker running; `script/start-containers` to bring up DB/Azurite; Overmind installed for integration tests.
- **Private modules:** Ensure Go module auth for `goproxy.githubapp.com` (e.g., `gh auth login` or `GITHUB_TOKEN` with `read:packages`).

## 🛠 Local development
- **Bootstrap tools:** `script/bootstrap` (installs pre-commit, Overmind, protobuf, golangci-lint, etc.).
- **Start service:** `script/server` (or `go run ./cmd/api`) — defaults to port 9097.
- **Seed dev data:** `script/seed-dev-data`.
- **Useful scripts:** `script/start-containers`, `script/migrate`, `script/resolve-dependencies`.
- **Env vars:** See `internal/config/config.go` for defaults (DB, Azure, Cosmos, Spokes, Twirp, HMAC). Set `DEV_STANDALONE_MODE=true` to mock Spokes; set `DEV_FORCE_HMAC_AUTHENTICATION=true` to enforce HMAC locally.

## 🧹 Coding standards
- **Format:** `gofmt -w`; enforced via pre-commit.
- **Lint:** `golangci-lint` pinned in `.pre-commit-config.yaml` / `Makefile`.
- **Imports & layout:** Follow Go module conventions; organize packages under `cmd/`, `internal/`, `pkg/`.
- **Errors:** Wrap with context (`%w`); prefer sentinel errors for comparison.
- **Hooks:** `pre-commit install` (or run `make lint` before commits).

## 🔐 Security & secrets
- Never hard-code secrets; use env vars / Vault (e.g., `MONOLITH_TWIRP_HMAC_KEY`).
- Handle PII carefully; avoid logging sensitive data.

## 📈 Observability
- Use `internal/contextlogger` with GitHub Telemetry Go (`github-telemetry-go`).
- Tracing configured via `internal/config/tracing.go` (OpenTelemetry).
- Add structured fields (no string interpolation); follow PR template’s Observability guidance (Semantic Conventions).

## 📄 Pull requests
- Use the PR template; note risk level and mitigation/rollback.
- Document feature flags and GHES impact/backporting needs.
- Required checks live in `.github/workflows/`; mirror them locally with `make lint` + `make test`.

## 📌 Service-specific notes
- Cloud vs GHES storage/retention differences (see **Environments**).
- GHES discards non-default branch snapshots immediately.
- Feature flags are unavailable in GHES; ensure safe defaults.

## 🧭 Working on issues
1. Understand the issue; consult `docs/glossary.md`.
2. Clarify scope if needed.
3. Write a failing test; confirm it fails with a clear message.
4. Propose your approach; especially for complex changes.
5. Implement incrementally; gate risky changes with feature flags.
6. Run lint + relevant tests (unit + integration).
7. Complete `.github/pull_request_template.md` (risk, flags, rollback, observability, backports).
