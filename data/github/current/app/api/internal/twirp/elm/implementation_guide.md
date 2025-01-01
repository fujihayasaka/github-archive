# ELM Migration API Implementation Guide

## Overview

ELM (Enterprise Live Migrations) APIs use a gem-based ownership model where each team owns their proto definitions and corresponding Ruby gem. This guide covers the monolith implementation side - for complete development workflows, see the [ELM API Guidelines](https://github.com/github/migrations-vnext/tree/main/docs/elm-api-guidelines).

## Current Structure

```text
Teams and their gems:
├── @github/c2c-actions → monolith-twirp-elm-actions
├── @github/pull-requests → monolith-twirp-elm-pull-requests (future)
└── @github/issues → monolith-twirp-elm-issues (future)
```

## How It Works

### 1. Proto Definitions & API Architecture

- **Source of truth**: [`github/migrations-vnext`](https://github.com/github/migrations-vnext) repo (`internal/proto/elm/`)
- **Team gems**: Auto-generated from proto definitions (`monolith-twirp-elm-{team}`)
- **Migration gem**: `mvnd` gem (requires team gems to avoid duplication)
- **API handlers**: `app/api/internal/twirp/elm/` (monolith implementations)

### 2. Team Ownership

Each team owns:

- Proto definitions in [`github/migrations-vnext`](https://github.com/github/migrations-vnext) repo
- Generated Ruby gem (`monolith-twirp-elm-{team}`)
- Handler implementations in monolith
- API documentation and integration

### 3. Gem Architecture

**Why this architecture exists:**

```text
GHES Export → ELM API (team + mvnd gems) → Migration Pipeline → DAG → Proxima
```

**Team Gems** (`monolith-twirp-elm-{team}`):

- Package proto definitions from `internal/proto/elm/{team}/`
- Owned by product teams
- Used by export/import API handlers

**MVN Gem** (`mvnd`):

- Requires team gems to avoid duplication
- Provides types for migration pipeline integration
- Owned by migrations team

**Auto-linking**: Running `make build-protobufs` in migrations-vnext automatically creates the linking between gems.

## Development Workflow

### Making Changes (Team Perspective)

**Complete workflow**: Follow the [Development Workflow Guidelines](https://github.com/github/migrations-vnext/blob/main/docs/elm-api-guidelines/development-workflow-guidelines.md) for full steps.

**Summary**:

1. **Update proto** in `migrations-vnext/internal/proto/elm/<your_team_name>`
2. **Generate gems** via `make build-protobufs` and `make generate-protobuf-gems`
3. **Update monolith** Gemfile to use new team gem version
4. **Implement handlers** following Twirp best practices
5. **Deploy** monolith changes

### Local Testing: Making Twirp Changes

1. **Update `.proto` files** in migrations-vnext
2. **Build local gems** using `make generate-protobuf-gems`
3. **Copy to monolith** `vendor/cache`
4. **Test changes** in both GitHub and ELM
5. **Merge proto changes** to `main` in migrations-vnext
6. **Clean up** temporary vendored gems and update Gemfile.lock

**Important**: Vendor **team gems separately** from `mvnd` gem to avoid backport issues with older GHES versions.

## API Requirements

### 1. Naming Conventions

- **Export**: `Export{Resource}Request/Response`
- **Import**: `Import{Resource}Request/Response`
- **Services**: `Export/Import{Resource}API`
- **Packages**: `elm.{team}.v{version}`

### 2. Required Fields

Every export response must include:

```ruby
# Required DAG fields
resource_id: "unique_resource_identifier"
repository_resource_id: "repository_owner_identifier"
```

### 3. Performance Requirements

- **Batch operations**: Avoid single-resource calls
- **Pagination**: Required for large datasets
- **Graceful degradation**: Partial failures don't break batches
- **Idempotency**: Safe to retry operations

## Example: Actions Team Setup

### Gem Configuration

```ruby
# Gemfile
gem "monolith-twirp-elm-actions", "1.1.0"
gem "mvnd", "0.x.x" # Contains linking to team gems
```

### Handler Implementation

After both repos have new proto definitions, add handlers and clients in the monolith.

Implement handler classes following [Twirp Implementation Guidelines](https://github.com/github/monolith-twirp/blob/master/docs/implementation.md).

Implement clients following [Usage Guidelines](https://github.com/github/monolith-twirp/blob/master/docs/usage.md).

### Current Implementation

```ruby
# Gemfile
gem "monolith-twirp-elm-actions", "1.1.0"
```

```ruby
# Handler: app/api/internal/twirp/elm/actions/v1/export_commit_status_checks_api_handler.rb
require "monolith-twirp-elm-actions"

module Api::Internal::Twirp::Elm
  module Actions
    module V1
      class ExportCommitStatusChecksAPIHandler < Api::Internal::Twirp::Handler
        handles_service MonolithTwirp::Elm::Actions::V1::ExportCommitStatusChecksAPIService
        allow_access_for :client, allowed_clients: %w[elm migrations_vnext]

        def export_commit_status_checks(req, env)
          # Implementation returns response hashes following Octoshift pattern
          # Twirp automatically converts hashes to protobuf objects
        end
      end
    end
  end
end
```

## Development Patterns

### Making Non-Breaking Changes

```bash
# 1. Update proto in migrations-vnext
cd migrations-vnext
# Edit internal/proto/elm/actions/v1/export_commit_status_checks.proto
# Add new optional field

# 2. Test locally in monolith
cd github/github
# Update handler implementation if needed

# 3. Merge and publish gem
# CI in migrations-vnext builds and publishes gem

# 4. Update monolith
bundle update monolith-twirp-elm-actions
```

## Benefits

### ✅ For Teams

- **Narrow scope**: Only update gems you own
- **Clear ownership**: Team controls their API definitions
- **Independent releases**: Don't wait for other teams
- **Type safety**: Generated code matches ELM exactly

### ✅ For ELM Team

- **Reduced coordination**: Teams self-manage their APIs
- **Controlled updates**: Review breaking changes only
- **Backward compatibility**: Multiple versions supported
- **Clear accountability**: Teams own their migration APIs

## Getting Started

### New Team Onboarding

1. **Create team directory** in `migrations-vnext/internal/proto/elm/<team_name>`
2. **Set up gem structure** following actions team example
3. **Update SERVICEOWNERS** for your team in `migrations-vnext` repo
4. **Add gem to monolith** and update SERVICEOWNERS there
5. **Implement handlers** in monolith

### Support

- **Proto questions**: @github/migrations-vnext
- **Breaking changes**: @github/migrations-vnext + your team
- **Gem issues**: Your team + @github/migrations-vnext
- **Migration coordination**: @github/migrations-vnext
