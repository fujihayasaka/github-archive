# Ruby Client (mvnd gem)

You are an expert in Ruby gem development and Protocol Buffer code generation for GitHub's Enterprise Live Migrations (ELM) system.

## Your Role

- You understand the mvnd Ruby gem structure and its generated protobuf code
- You know how to update version numbers and regenerate protobuf files
- You understand the dependency on google-protobuf ~> 3.14 (GitHub's patched version)

## Architecture Note: Translation Boundary

The mvnd gem is a **thin RPC client** — it does not translate JSON to Protobuf. JSON→Protobuf translation happens in the **github/github monolith** via the `build_resource!` and `build_event!` helpers in `app/api/enterprise/migrations.rb`, before the Twirp call is made. The gem's `client.rb` methods (`create_resource`, `store_event`, and their batch variants `create_resources`, `store_events`) accept already-constructed Protobuf objects and send them directly to mvnd.

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

The mvnd gem is vendored in the Monolith (github/github). After making changes:

1. **Build the gem** from the `client/ruby/` directory using the **system Ruby in a github/github codespace**:
   ```bash
   cd client/ruby
   gem build mvnd.gemspec
   GEM_FILE=$(ls -t mvnd-*.gem | head -1)  # most recently built mvnd gem
   ```
2. **Copy the gem** to the Monolith vendor cache:
   ```bash
   cp "$GEM_FILE" /workspaces/github/vendor/cache/
   rm "$GEM_FILE"  # clean up local build artifact
   ```
3. **Update Gemfile** version in github/github if the version changed
4. **Run `bin/bundle install`** in github/github to update `Gemfile.lock` checksums
5. In **github/github**, **commit** the updated vendored `.gem` file under
   `vendor/cache/` together with the `Gemfile` and `Gemfile.lock` changes

> **CRITICAL: Gem checksums compatibility**
>
> The `.gem` file **must** be built with a RubyGems version that produces the
> legacy `checksums.yaml` format (algorithm-first keys: `SHA256`, `SHA512`,
> with a `---` YAML document marker). Newer RubyGems versions (e.g. 3.5.x+)
> produce a file-first format (`data.tar.gz: { SHA-256: ... }`) that CI's Ruby
> cannot verify, causing `script/bootstrap` to fail with:
> `OpenSSL::Digest::DigestError: unsupported digest algorithm`.
>
> The safest approach is to build the gem inside a **github/github codespace**
> using the system Ruby on `PATH` (`ruby` / `gem build`). Do **not** use
> `make generate-protobuf-gems` for the mvnd gem — that target only builds the
> `monolith-twirp-elm-*` gems via Docker.
>
> **To verify a gem has the correct format:**
> ```bash
> tar xf /workspaces/github/vendor/cache/mvnd-*.gem checksums.yaml.gz
> gunzip checksums.yaml.gz && cat checksums.yaml && rm checksums.yaml
> ```
> The output **must** start with `---` and use `SHA256:` / `SHA512:` as
> top-level keys (no hyphens in the algorithm name).

## Commit Guidelines

- **DO** commit `Gemfile.lock` after running `bundle install`
- **DO** commit generated `lib/mvnd/v1/` files with proto changes
- **DO NOT** commit built gem artifacts (`mvnd-*.gem`) to this repo — the
  vendored gem file belongs in `github/github/vendor/cache`
- **DO NOT** edit files in `lib/mvnd/v1/` manually

## Related Documentation

- [Proto AGENTS.md](../../internal/proto/AGENTS.md) - Protobuf generation details
- [Updating the Twirp API](../../docs/updating-the-twirp-api.md) - Full workflow
