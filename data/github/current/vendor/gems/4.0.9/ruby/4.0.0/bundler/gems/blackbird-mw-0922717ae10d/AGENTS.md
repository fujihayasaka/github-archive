This is a Go-based repository containing middleware for the blackbird code search engine. It includes a Ruby and Go Twirp client. Please follow these guidelines when contributing.

## Code Standards

### Required Before Each Commit
- Run `make format` before committing any changes to ensure proper code formatting
- This will run `go fmt` on all Go files to maintain consistent style

### Development Flow
- Bootstrap: `make bootstrap` (required for initial setup or when clibs change)
- Build: `make build`
- Test: `make test` (unit tests)
- Lint: `make lint` (runs golangci-lint)
- Full check: `make all` (includes format, build, test)

### Testing
- Unit tests: `make test`
- End-to-end tests: `make test-e2e` (requires Docker)
- Database tests: `make test-db` (requires Docker)
- Redis tests: `make test-redis` (requires Docker)
- Ruby tests: `make test-ruby`

## Repository Structure
- `cmd/`: Main service entry points and executables
  - `blackbird-admin/`: Admin UI backend and chatops server
  - `blackbird-ingest/`: Ingest pipeline
  - `blackbird-query/`: Query server
  - `blackbird-prober/`: Probers
  - `blackbird-maintenance/`: Maintenance job
  - `blackbird-embeddings-maintenance/`: Embeddings maintenance
- `internal/`: Internal packages for all service logic
- `lib/`: C static libraries (do not modify)
- `admin-frontend/`: Admin interface (React)
- `config/`: Configuration files and templates
- `docs/`: Documentation
- `proto/`: Protocol buffer service and message definitions
- `ruby/`: Ruby client implementation
- `schemas/`: Database schemas (managed with Skeema)
- `gen/`: Generated code from protobuf (Go client)
- `deps/`: Git submodules including spokes-proto
- `vendor/`: Vendored Go dependencies (run `go mod vendor` to update)

## Key Guidelines
1. Follow Go best practices and idiomatic patterns
2. Maintain existing code structure and organization
3. Write unit tests for new functionality. Use table-driven unit tests when possible.
4. Document public APIs

## Important Notes
- This repo uses CGO with static libraries from the blackbird repo
- Environment variables are loaded from `.env` and `.envrc` (use direnv)
- Docker is required for end-to-end and database tests
- Database schema changes require the `migration:for:review` label and DBA approval
- Be careful when updating the `sarama` Kafka dependency (historical issues with upgrades)
