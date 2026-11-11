# Test Helper Service

A standalone REST API service that allows Go integration tests to create test fixtures using FactoryBot from the Rails application.

## Overview

This service exposes a simple REST endpoint that accepts a fixture type and optional attributes, then creates the fixture using `FactoryBot.create()` and returns the JSON-serialized result.

**Important:** This service is ONLY available in the test environment and will refuse to start in any other environment.

## Architecture

- **App**: `lib/test_helper_service/app.rb` (Business logic)
- **Rack App**: `lib/test_helper_service/config.ru` (Standalone application)
- **Startup Script**: `script/test-helper-service-server`

## Usage

### Starting the Service

```bash
# Set environment to test
export RAILS_ENV=test

# Start the service (default port: 9292)
./script/test-helper-service-server

# Or specify a custom port
TEST_HELPER_SERVICE_PORT=8080 ./script/test-helper-service-server
```

### Endpoints

- **Health Check**: `GET http://localhost:9292/health`
- **Service Info**: `GET http://localhost:9292/`
- **Create Fixture**: `POST http://localhost:9292/fixtures`
- **Reset Test State**: `POST http://localhost:9292/reset`
- **Truncate All Tables**: `POST http://localhost:9292/truncate`

### Example Walkthrough

#### Step 1: Start the service

```bash
export RAILS_ENV=test
./script/test-helper-service-server
```

Wait for the service to start. You should see:

```text
[2025-11-19 08:46:02] INFO  WEBrick::HTTPServer#start: pid=73825 port=9292
```

#### Step 2: Test the health check

In a separate terminal:

```bash
curl http://localhost:9292/health
```

Response:

```
OK
```

#### Step 3: Create fixtures

```bash
# Create a repository
curl -X POST http://localhost:9292/fixtures \
  -H "Content-Type: application/json" \
  -d '{"fixture_type": "repository", "attributes": {"name": "test-repo"}}'
```

Response:

```json
{
  "fixture": {
    "id": 9,
    "name": "test-repo",
    "owner_id": 34,
    "parent_id": null,
    "sandbox": null,
    "updated_at": "2025-11-19T08:51:53.000-08:00",
    "created_at": "2025-11-19T07:51:53.000-08:00",
    "public": true,
    "description": null,
    "homepage": null,
    "source_id": 9,
    "public_push": null,
    "disk_usage": 0,
    "locked": false,
    "pushed_at": "2025-11-19T07:51:53.000-08:00",
    "watcher_count": 0,
    "public_fork_count": 0,
    "primary_language_name_id": null,
    "has_issues": true,
    "has_wiki": true,
    "has_downloads": true,
    "raw_data": null,
    "organization_id": null,
    "disabled_at": null,
    "disabled_by": null,
    "disabling_reason": null,
    "health_status": null,
    "pushed_at_usec": 952474,
    "active": true,
    "reflog_sync_enabled": false,
    "made_public_at": "2025-11-19T08:51:53.000-08:00",
    "user_hidden": 0,
    "maintained": true,
    "template": false,
    "owner_login": "user-b4e1d2904152eba6931093d4",
    "world_writable_wiki": false,
    "refset_updated_at": null,
    "disabling_detail": null,
    "archived_at": null,
    "deleted_at": null
  },
  "id": 9
}
```

### Additional Examples

```bash
# Create a user with specific attributes
curl -X POST http://localhost:9292/fixtures \
  -H "Content-Type: application/json" \
  -d '{"fixture_type": "user", "attributes": {"login": "testuser"}}'

# Create a repository with an owner
curl -X POST http://localhost:9292/fixtures \
  -H "Content-Type: application/json" \
  -d '{"fixture_type": "repository", "attributes": {"name": "my-repo", "owner_id": 123}}'

# Reset test state (calls reset_everything from GitHub::BasicTestCase)
curl -X POST http://localhost:9292/reset \
  -H "Content-Length: 0"

# Truncate all database tables
curl -X POST http://localhost:9292/truncate \
  -H "Content-Length: 0"
```

### Response Format

**Successful response:**

```json
{
  "fixture": {"id": 123, "login": "testuser", ...},
  "id": 123
}
```

**Error response:**

```json
{
  "error": "fixture_type is required"
}
```

## Go Client Usage

```go
package main

import (
    "bytes"
    "context"
    "encoding/json"
    "fmt"
    "io"
    "net/http"
)

type FixtureRequest struct {
    FixtureType string                 `json:"fixture_type"`
    Attributes  map[string]interface{} `json:"attributes"`
}

type FixtureResponse struct {
    Fixture map[string]interface{} `json:"fixture"`
    ID      int64                  `json:"id"`
}

func createFixture(ctx context.Context, fixtureType string, attrs map[string]interface{}) (*FixtureResponse, error) {
    req := FixtureRequest{
        FixtureType: fixtureType,
        Attributes:  attrs,
    }

    body, _ := json.Marshal(req)
    httpReq, _ := http.NewRequestWithContext(ctx, "POST", "http://localhost:9292/fixtures", bytes.NewReader(body))
    httpReq.Header.Set("Content-Type", "application/json")

    resp, err := http.DefaultClient.Do(httpReq)
    if err != nil {
        return nil, err
    }
    defer resp.Body.Close()

    respBody, _ := io.ReadAll(resp.Body)

    if resp.StatusCode != 200 {
        return nil, fmt.Errorf("error: %s", string(respBody))
    }

    var result FixtureResponse
    json.Unmarshal(respBody, &result)
    return &result, nil
}

// Example usage
func main() {
    // Create a user
    user, err := createFixture(context.Background(), "user", map[string]interface{}{
        "login": "testuser",
    })
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("Created user with ID: %d\n", user.ID)

    // Create a repository
    repo, err := createFixture(context.Background(), "repository", map[string]interface{}{
        "name": "test-repo",
        "owner_id": user.ID,
    })
    if err != nil {
        log.Fatal(err)
    }
    fmt.Printf("Created repository with ID: %d\n", repo.ID)
}
```

## Supported Fixture Types

Any fixture type defined in FactoryBot can be created. Common examples:

- `user`
- `repository`
- `organization`
- `issue`
- `pull_request`
- And any other factory defined in the test suite

## Error Handling

The service returns HTTP error codes with JSON error messages:

- `400 Bad Request`: Invalid fixture type, malformed JSON, or invalid attributes
- `403 Forbidden`: Service called outside test environment
- `405 Method Not Allowed`: Non-POST request
- `500 Internal Server Error`: Unexpected errors during fixture creation

## Security

- **Environment Restriction**: The service explicitly checks that `RAILS_ENV=test` and will refuse to start otherwise
- **Network Isolation**: Should only be accessible from within the Docker network
- **No Authentication**: The service does not require authentication as it runs in a trusted test environment

## Testing

Run the test suite:

```bash
bin/rails test test/lib/test_helper_service/app_test.rb
```

## Docker Integration

When running Go integration tests in Docker Compose:

```yaml
services:
  test-fixture-service:
    build: .
    command: ./script/test-fixture-service-server
    environment:
      - RAILS_ENV=test
    ports:
      - "9292:9292"
    networks:
      - test-network

  go-integration-tests:
    build: ./go-tests
    environment:
      - TEST_FIXTURE_SERVICE_URL=http://test-fixture-service:9292
    depends_on:
      - test-fixture-service
    networks:
      - test-network

networks:
  test-network:
```

## Test State Management

### Reset Test State

The `/reset` endpoint calls `reset_everything` from `GitHub::BasicTestCase` and re-initializes DGit fileservers:

```bash
curl -X POST http://localhost:9292/reset -H "Content-Length: 0"
```

Response:
```json
{"success": true, "message": "Reset completed"}
```

This is useful for cleaning up test state between test runs while preserving necessary seed data.

### Truncate All Tables

The `/truncate` endpoint truncates all database tables across all clusters (preserving `schema_migrations` and `ar_internal_metadata`):

```bash
curl -X POST http://localhost:9292/truncate -H "Content-Length: 0"
```

Response:
```json
{"success": true, "message": "Databases truncated"}
```

This provides a faster alternative to a full reset when you need a completely clean database state.
