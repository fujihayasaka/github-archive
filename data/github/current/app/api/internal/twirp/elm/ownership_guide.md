# ELM Migration API Team Ownership Guide

## Overview

ELM migration APIs use a gem-based ownership model where each team owns their proto definitions and corresponding Ruby gem.

## Current Structure

```
Teams and their gems:
├── @github/c2c-actions → monolith-twirp-elm-actions
├── @github/pull-requests → monolith-twirp-elm-pull-requests (future)
└── @github/issues → monolith-twirp-elm-issues (future)
```

## How It Works

### 1. Proto Definitions & API endpoints
- **Source of truth**: [`github/migrations-vnext`](https://github.com/github/migrations-vnext) repo
- **Generated code**: Distributed via team-specific gems (installed in the monolith)
- **API handlers that use the definitions**: `app/api/internal/twirp/elm/` (monolith implementations)

### 2. Team Ownership
Each team owns:
- Proto definitions in [`github/migrations-vnext`](https://github.com/github/migrations-vnext) repo
- Generated Ruby gem
- Handler implementations in monolith
- API documentation and examples

### 3. Workflow

#### Making Changes (Team Perspective)
1. **Update proto** in `migrations-vnext/internal/proto/elm/<your_team_name>`
2. **Test locally** (see below)
3. **Generate gem** via CI in `migrations-vnext`
4. **Update monolith** Gemfile to use new gem version
5. **Deploy** monolith changes

### 4. Local Testing: Making Twirp Changes between ELM and GitHub

We use GitHub's [monolith-twirp](https://github.com/github/monolith-twirp) for internal APIs between ELM (migrations-vnext) and GitHub. The summary of how to make protobuf changes:

1. Update the `.proto` files
2. Build a local gem
3. Test your changes in GitHub and ELM using the local gem
4. Merge proto-only changes to `main` in `github/migrations-vnext`
5. Wait for the build to complete and publish the new gem to Octofactory
6. In `github/github`, delete the temporary vendored gem from `vendor/cache` and its installed files from `vendor/gems/current/`
7. Undo the changes to `Gemfile.lock`
8. Run `bin/bundle install && bni/bump-sorbet-and-tapioca`

#### Updating the .proto files

ELM's protobuf files are in the [/internal/proto/elm/](https://github.com/github/migrations-vnext/tree/main/internal/proto/elm/) directory and define schemas used in Twirp calls.

- Add a new proto or append to existing proto following [Twirp Definition Guidelines](https://github.com/github/monolith-twirp/blob/master/docs/definition.md)
- Increase the VERSION for your team accordingly to indicate a new gem will be generated

#### Build Gem Locally

We use [monolith-twirp-tools](https://github.com/github/monolith-twirp-tools) to generate Twirp gems via build-pipeline (bp-agents).

1. Pull the tools container:
   ```shell
   docker pull ghcr.io/github/monolith-twirp-tools/gen-ruby:latest
   ```

2. In the migrations-vnext folder, generate the gems:
   ```shell
   script/build-twirp-gems
   ```

3. Copy built gems to `vendor/cache` in the monolith:
   ```shell
   # Example output shows where to copy:
   # tmp/twirp-gems/monolith-twirp-elm-actions-1.1.0.gem
   ```

4. Update your Gemfile to the new version (separate PR from proto changes)

### 5. Creating API Endpoints in Monolith

After both repos have new proto definitions, add handlers and clients in the monolith.

Implement handler classes following [Twirp Implementation Guidelines](https://github.com/github/monolith-twirp/blob/master/docs/implementation.md).

Implement clients following [Usage Guidelines](https://github.com/github/monolith-twirp/blob/master/docs/usage.md).

## Example: Actions Team Implementation

### Current Setup

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

### Making a Non-Breaking Change

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

- **Proto questions**: @github/enterprise-live-migrations
- **Breaking changes**: @github/enterprise-live-migrations + your team
- **Gem issues**: Your team + @github/enterprise-live-migrations
- **Migration coordination**: @github/enterprise-live-migrations
