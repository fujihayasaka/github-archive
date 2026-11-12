# Copilot Instructions for dependabot-api

You, or Copilot, may update these instructions as you find things that are inaccurate, missing, or could be improved to help Copilot better assist with this codebase.

## Overview

This is a **Rails API-only application** that powers GitHub's Dependabot service. It uses **Coach** (middleware-based controllers) instead of standard Rails controllers, **Aqueduct** for background jobs, and **Hydro** for event streaming.

## Running Commands

All development happens inside Docker containers. Commands should be run using the provided scripts which handle the container environment automatically.

### Setup

```bash
script/setup          # Use this to set up or update the development environment (installs dependencies, builds containers)
script/update         # Update after pulling changes
script/app-env        # Run one-off arbitrary commands inside the app container
```

**Important:** If tests or linting fail with missing gem errors, run `script/setup` first to install dependencies.

### Testing

Always use `script/test` to run tests - this ensures tests run inside the Docker container with the correct environment:

```bash
script/test                              # Run all specs
script/test spec/models/foo_spec.rb      # Run specific file
script/test spec/models/foo_spec.rb:42   # Run specific line
script/test --staged                     # Run specs for staged files only
script/test --format doc                 # Pass RSpec options
```

**Do NOT** run `bundle exec rspec` directly - it will fail due to missing environment variables.

**Re-record VCR cassettes:**
```bash
VCR=all DEPENDABOT_TEST_ACCESS_TOKEN=<token> script/test spec/path/to_spec.rb
```

**Test metadata tags** (add to `describe`, `context`, or `it` blocks):
- `enterprise: true` - Run only in enterprise mode
- `cloud: true` - Run only in cloud mode
- `proxima: true/false` - Toggle proxima mode

```ruby
it "does something enterprise-specific", enterprise: true do
  # This test only runs in enterprise mode
end

context "when proxima is enabled", proxima: true do
  # These tests only run in proxima mode
end
```

### Linting

Always use `script/lint` to run the linter - this ensures it runs inside the Docker container:

```bash
script/lint                    # Run RuboCop
script/lint --strict           # Strict mode (fail on warnings)
script/lint --regenerate-todo  # Regenerate .rubocop_todo.yml
```

**Do NOT** run `bundle exec rubocop` directly.

### Other Development Commands

```bash
script/server         # Start the Rails application
script/console        # Open Rails console
script/create-databases      # Create development/test databases
script/migrate               # Run migrations
script/rollback              # Rollback last migration
script/generate-migration <name>  # Generate new migration
```

## Project Structure

| Directory | Purpose |
|-----------|---------|
| `app/actions/` | Business logic classes (command pattern with `run` method) |
| `app/coach/` | Coach middleware and routes (not standard Rails controllers) |
| `app/controllers/` | Traditional controllers (ChatOps only) |
| `app/hydro/` | Hydro event definitions |
| `app/jobs/` | ActiveJob background jobs (via Aqueduct) |
| `app/models/` | ActiveRecord models |
| `app/processors/` | Hydro event processors |
| `app/services/` | Twirp RPC service handlers |
| `app/state_machines/` | Statesman state machines |
| `lib/` | Shared libraries and utilities |
| `spec/` | RSpec tests (mirrors app/ structure) |

## Code Patterns

### Actions Pattern
Business logic is encapsulated in action classes with a `run` method:

```ruby
class DoSomething
  def initialize(param:)
    @param = param
  end

  def run
    # Business logic here
  end
end
```

### State Machines
Uses Statesman gem. Key state machines: `Account`, `PullRequest`, `UpdateJob`, `UpdateConfig`.

### Coach Routes
Request handling uses Coach middleware, not standard Rails controllers. Routes are defined in `config/routes.rb` using Coach::Router, with handler classes in `app/coach/routes/`.

### Hydro Events
Event streaming via Hydro. Processors extend `ApplicationProcessor`.

### Feature Flags
Use **monolith feature flags** via `monolith_feature_enabled?`.

```ruby
# On Repo or Account models
repo.monolith_feature_enabled?(:dependabot_my_feature)
account.monolith_feature_enabled?(:dependabot_my_feature)

# Directly on Application (with actor)
Dependabot::Application.monolith_feature_enabled?(
  feature: :dependabot_my_feature,
  actor: repo,  # or account, or nil for global
)
```

**Testing:** Use `stub_monolith_feature(:feature_name, actor: repo.monolith_actor, enabled: true)`.

**Deprecated:** `config_feature_enabled?` / chatops features are deprecated. Use monolith flags for new features.

## Testing Conventions

- Test files: `spec/**/*_spec.rb` (mirrors `app/` and `lib/` structure)
- Factories: `spec/factories/`
- VCR cassettes: `spec/fixtures/vcr_cassettes/`
- Support helpers: `spec/support/`

Example test:

```ruby
RSpec.describe DoSomething do
  describe "#run" do
    it "does the thing" do
      result = described_class.new(param: value).run
      expect(result).to be_success
    end
  end
end
```

## Type Checking

Uses **Sorbet** for type checking. RBI files are in `sorbet/rbi/`. If type checking fails (i.e., the `bundle exec srb tc` command fails), ensure the RBI type definition files are up to date using Tapioca by running this command:

```shell
script/app-env bundle exec tapioca gem
```

## Database

- **MySQL 8.0** with Trilogy client
- Migrations use GitHub's Skeefree for production
- Enterprise schema: `db/enterprise_structure.sql`
- Main schema: `db/structure.sql`

## Key Dependencies

- `coach` - Middleware-based controllers
- `dependabot-omnibus` - Core Dependabot functionality
- `aqueduct-rails` - GitHub's job queue
- `hydro-client` - GitHub's event streaming
- `statesman` - State machines
- `twirp` - RPC services
- `trilogy` - MySQL client

## Environment

- Copy `.env.local.example` to `.env.local` for local configuration
- Uses Prius gem for environment variable management

## Pull Request Descriptions

When you open a PR (including via Copilot), fill in the project's PR template (`.github/pull_request_template.md`). Leftover `<!-- ... -->` placeholder comments are fine — they're for guidance, not something a reviewer will flag — but each section should have a real answer alongside (or in place of) the placeholder. Specifically:

- **What are you trying to accomplish?** — describe both the *what* and the *why*. Don't leave the section without any answer.
- **Which environments does this change target?** — keep the relevant `Production` (`dotcom`/`proxima`/`GHES`) or `Non-production` checkboxes ticked. If a Production change excludes `proxima` or `GHES`, briefly explain why.
- **Risk Assessment** — check exactly one of Low / Medium / High.
- **Is there a Feature Flag?** — check exactly one of Yes / No. If **Yes**, name the flag below the checklist; the name must match the symbol passed to `monolith_feature_enabled?` in the diff. If **No** for a production change, briefly say why no flag is needed.
- **How will you know you've accomplished your goal?** — mention dashboards, metrics, or a reproduction.

If the PR uses the alternate `.github/PULL_REQUEST_TEMPLATE/production_change_request.md`, the same idea applies — fill in environment, risk, and validation sections.
