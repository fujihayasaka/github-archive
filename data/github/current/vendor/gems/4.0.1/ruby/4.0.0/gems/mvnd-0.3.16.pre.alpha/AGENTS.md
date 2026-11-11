# Ruby Client (mvnd gem)

You are an expert in Ruby gem development and Protocol Buffer code generation for GitHub's Enterprise Live Migrations (ELM) system.

## Your Role

- You understand the mvnd Ruby gem structure and its generated protobuf code
- You know how to update version numbers and regenerate protobuf files
- You understand the dependency on google-protobuf ~> 3.14 (GitHub's patched version)

## Project Knowledge

### Tech Stack

- **Ruby >= 3.1.0**: Runtime requirement
- **Twirp ~> 1.10**: RPC framework
- **google-protobuf ~> 3.14**: Protocol Buffers (GitHub's patched version)
- **protoc@v3.15.0**: Code generation tool

### File Structure

```
client/ruby/
├── AGENTS.md              # This file
├── Gemfile                # Development dependencies
├── Gemfile.lock           # Locked dependency versions (commit after bundle install)
├── mvnd.gemspec           # Gem specification
├── lib/
│   └── mvnd/
│       ├── version.rb     # VERSION constant - bump for proto changes
│       ├── client.rb      # HTTP client implementation
│       ├── hmac_middleware.rb
│       ├── twirp_error.rb
│       └── v1/            # GENERATED protobuf code
│           ├── migration_pb.rb
│           ├── migration_twirp.rb
│           ├── resource_pb.rb
│           ├── resource_twirp.rb
│           ├── event_pb.rb
│           ├── entities/  # Entity message definitions
│           │   ├── issue_pb.rb
│           │   ├── pull_request_pb.rb
│           │   └── ...
│           ├── actions/   # ELM wrapper files
│           ├── data/
│           ├── issues/
│           ├── organizations/
│           └── repositories/
├── script/
│   └── test               # Test runner
└── test/                  # Unit tests
```

### Generated vs Manual Files

| File Pattern | Status | Notes |
|--------------|--------|-------|
| `lib/mvnd/v1/*_pb.rb` | **GENERATED** | Do not edit manually |
| `lib/mvnd/v1/*_twirp.rb` | **GENERATED** | Do not edit manually |
| `lib/mvnd/v1/entities/*` | **GENERATED** | Do not edit manually |
| `lib/mvnd/version.rb` | **MANUAL** | Bump version here |
| `lib/mvnd/client.rb` | **MANUAL** | Client implementation |
| `Gemfile.lock` | **MANUAL** | Update via `bundle install` |

## Commands

**Regenerate Ruby protobuf files (from repository root):**

```bash
make build-protobufs
```

**Update Gemfile.lock after version bump:**

```bash
cd client/ruby && bundle install
```

**Run tests:**

```bash
cd client/ruby && ./script/test
# Or from repo root:
make test-ruby-client
```

## Version Management

### When to Bump Version

Bump the version in `lib/mvnd/version.rb` whenever:

- Adding new entity protos in `internal/proto/hydro/.../entities/`
- Adding new RPCs to `migration.proto`
- Modifying existing message or service definitions
- Any change to `internal/proto/hydro/` that affects generated Ruby code

### Version Format

```ruby
# lib/mvnd/version.rb
module Mvnd
  VERSION = '0.3.6-alpha'  # Increment the patch version
end
```

Use semantic versioning with `-alpha` suffix during development.

## Platform Constraints

### Linux Required for Generation

The Ruby protobuf generation script (`internal/proto/generate_mvn_ruby`) **requires Linux**. On macOS ARM, the script will exit with a warning:

```
WARNING: unable to update the mvnd gem from macOS; the protoc version is not
available on the ARM architecture...
```

**Solution:** Use a Linux codespace for proto changes that affect Ruby code.

### Protobuf Version Lock

The gem depends on GitHub's patched `google-protobuf ~> 3.14`. This is required for compatibility with the Monolith (github/github). Do not upgrade this dependency without coordinating with the Monolith team.

## Common Workflows

### After Proto Changes

1. **Bump version** in `lib/mvnd/version.rb`
2. **Regenerate** from repo root: `make build-protobufs`
3. **Update `client.rb` wrapper methods** if any request/response messages gained, removed, or changed fields. The generated `_pb.rb` files update automatically, but the hand-written convenience methods in `client.rb` must be updated manually to accept and pass new fields. Use keyword arguments with safe defaults for backward compatibility.
4. **Update `test/client_test.rb`** to cover any new or changed fields.
5. **Update lockfile**: `cd client/ruby && bundle install`
6. **Run tests**: `make test-ruby-client`
7. **Commit** both proto changes and generated Ruby files together

### Using in github/github

The mvnd gem is used in the Monolith. After making changes:

1. Build the gem: `make generate-protobuf-gems` (from repo root)
2. Copy gem from `tmp/twirp-gems/gems/` to `github/vendor/cache`
3. Update Gemfile in github/github
4. Run `bundle install` in github/github

## Commit Guidelines

- **DO** commit `Gemfile.lock` after running `bundle install`
- **DO** commit generated `lib/mvnd/v1/` files with proto changes
- **DO NOT** commit gem files (`.gem`) - these go in github/vendor/cache
- **DO NOT** edit files in `lib/mvnd/v1/` manually

## Related Documentation

- [Proto AGENTS.md](../../internal/proto/AGENTS.md) - Protobuf generation details
- [Updating the Twirp API](../../docs/updating-the-twirp-api.md) - Full workflow
