# Ruby Client (elm_exporter gem)

You are an expert in Ruby gem development and Protocol Buffer / Twirp code
generation for GitHub's Enterprise Live Migrations (ELM) system.

## Your Role

- You understand the `elm_exporter` Ruby gem structure and its generated
  protobuf/Twirp code for the `MigrationManagerAPI` service.
- You know how to regenerate the protobuf/Twirp sources and bump the version.
- You understand the dependency on `google-protobuf >= 3.14, < 4.0` and why the
  committed lockfile resolves a newer version.

## Architecture Note: Translation Boundary

The `elm_exporter` gem is a **thin Twirp RPC client**. It wraps the generated
`MigrationManagerAPIClient` with a small convenience layer (`client.rb`),
request signing (`hmac_middleware.rb`), and error handling (`twirp_error.rb`).
It does **not** contain business logic — callers in the github/github monolith
build requests and interpret responses.

## Project Knowledge

### Tech Stack

- **Ruby >= 3.1.0**: Runtime requirement
- **Twirp ~> 1.10**: RPC framework
- **google-protobuf ~> 3.14**: Protocol Buffers (GitHub's patched version; see
  "Protobuf Version Lock" below)
- **gen-ruby Docker image `protoc-3.15.4-g067dc6afa`**: code generation tool

### File Structure

```
client/ruby/
├── AGENTS.md                       # This file
├── Gemfile                         # Pulls deps from the gemspec
├── Gemfile.lock                    # Locked DEV/TEST versions (commit it)
├── elm_exporter.gemspec            # Gem specification
├── lib/
│   └── mvnd/
│       ├── elm_exporter.rb         # Loader (requires the files below)
│       └── elm_exporter/
│           ├── version.rb          # VERSION constant — bump for proto changes
│           ├── client.rb           # MANUAL: thin client wrapper
│           ├── hmac_middleware.rb  # MANUAL: Request-HMAC signing
│           ├── twirp_error.rb      # MANUAL: error wrapper
│           └── api/
│               └── v1/
│                   ├── api_pb.rb     # GENERATED — do not edit
│                   └── api_twirp.rb  # GENERATED — do not edit
├── script/
│   ├── generate                    # Regenerates api_pb.rb / api_twirp.rb
│   └── test                        # Test runner
└── test/
    └── client_test.rb              # Unit tests (Faraday test-adapter round-trip)
```

> Namespace: all classes live under `Mvnd::ElmExporter::Api::V1` (from the
> proto's `option ruby_package`), consistent with the `mvnd` gem's prior art.

### Generated vs Manual Files

| File Pattern | Status | Notes |
|--------------|--------|-------|
| `lib/mvnd/elm_exporter/api/v1/api_pb.rb` | **GENERATED** | Do not edit manually |
| `lib/mvnd/elm_exporter/api/v1/api_twirp.rb` | **GENERATED** | Do not edit manually |
| `lib/mvnd/elm_exporter/version.rb` | **MANUAL** | Bump version here |
| `lib/mvnd/elm_exporter/client.rb` | **MANUAL** | Client wrapper |
| `lib/mvnd/elm_exporter/hmac_middleware.rb` | **MANUAL** | Request signing |
| `lib/mvnd/elm_exporter/twirp_error.rb` | **MANUAL** | Error handling |
| `Gemfile.lock` | **MANUAL** | Update via `bundle install` |

## Commands

**Regenerate the protobuf/Twirp sources (from repository root):**

```bash
make generate-protobufs
```

Prefer `make generate-protobufs` — it regenerates **both** the Go and Ruby
clients so they never drift. Use `make generate-protobufs-ruby` only when you
deliberately want the Ruby sources alone. Either target wraps
`client/ruby/script/generate` for the Ruby half, which runs the `gen-ruby` Docker image
(pinned to `protoc-3.18.3-g067dc6afa`) against
`internal/proto/elm_exporter/schemas/migration_manager/v1/api.proto`, builds a
gem, and extracts only `api_pb.rb` / `api_twirp.rb` into `lib/`. You may need to
`docker login ghcr.io` first. See "Platform Constraints" for the image-version
rationale.

**Update Gemfile.lock:**

```bash
cd client/ruby && bundle install
```

**Run tests:**

```bash
cd client/ruby && ./script/test
# or: bundle exec ruby test/client_test.rb
```

## Version Management

Bump the version in `lib/mvnd/elm_exporter/version.rb` whenever:

- The `MigrationManagerAPI` proto gains/removes/changes RPCs or messages.
- Any change to `internal/proto/elm_exporter/.../api.proto` affects generated
  Ruby code.

```ruby
# lib/mvnd/elm_exporter/version.rb
module Mvnd
  module ElmExporter
    VERSION = "0.1.0.pre.alpha"  # increment for proto changes
  end
end
```

Use semantic versioning with a `.pre.alpha` suffix during development. Note the
**dotted** prerelease form (`0.1.0.pre.alpha`, not `0.1.0-alpha`): RubyGems
treats a hyphen as a platform suffix, so the dotted form is canonical and makes
the source version match the built `elm_exporter-0.1.0.pre.alpha.gem` filename.

## Platform Constraints

### Generator image version — DO NOT sync to the lint label

`script/generate` is pinned to the gen-ruby image
**`protoc-3.18.3-g067dc6afa`**. This is **intentionally different** from the
`protoc-3.15.4-g80c50a5ac` label in `.monolith-twirp.yml` used for linting:

- The lint image's `protoc-gen-twirp_ruby` plugin **cannot** generate proto3
  `optional` fields (e.g. `ListMigrationsRequest.status`) and fails with:
  `protoc-gen-twirp_ruby hasn't been updated to support optional fields in proto3`.
- `g067dc6afa` bundles a plugin build that supports proto3 `optional`.

**Do not "align" these versions** or regeneration will break.

### Post-generation cleanup

`script/generate` cleans up after itself, but be aware the image scaffolds
`Makefile`/`VERSION` files into every schema dir under
`internal/proto/elm_exporter/schemas` (including ones this gem doesn't own, e.g.
`elm_ipc`) and leaves built gems in `tmp/`. None of that belongs in a PR — only
`lib/.../api_pb.rb` and `api_twirp.rb` should change. The script reverts the
scaffolded files via `git checkout`/`git clean` scoped to the schema dir.

> ⚠️ If you are editing proto files (e.g. changing `option ruby_package`),
> **commit or stage those changes before running generation** — the cleanup
> step will otherwise discard uncommitted proto edits.

### Protobuf Version Lock (dev vs. runtime)

The gemspec declares `google-protobuf "~> 3.14"`. The monolith (github/github)
ships a **patched** `google-protobuf 3.14` fork, and this lower bound lets the
gem install there. The gem only works with that *patched* fork, not upstream
3.14 — do not raise this constraint without coordinating with the ELM team.

**Note on `Gemfile.lock`:** the committed lock resolves a newer
`google-protobuf` (e.g. `3.25.8`) because that is what Bundler picks on a normal
codespace. **This lock governs only this gem's dev/test loop** (`script/test`).
At runtime in the monolith the lock is ignored and the patched 3.14 fork is
used. This mirrors the `mvnd` gem, which has the same lock-vs-runtime split.

## Common Workflows

### After Proto Changes

1. **Stage/commit** any `api.proto` edits first (see cleanup warning above).
2. **Bump version** in `lib/mvnd/elm_exporter/version.rb`.
3. **Regenerate**: `make generate-protobufs` (regenerates both the Go and Ruby
   clients; use `make generate-protobufs-ruby` for the Ruby sources alone).
4. **Update `client.rb`** if request/response messages gained, removed, or
   changed fields — the generated `_pb.rb` updates automatically, but the
   hand-written wrapper methods do not.
5. **Update `test/client_test.rb`** to cover new/changed fields.
6. **Update lockfile**: `cd client/ruby && bundle install`.
7. **Run tests**: `cd client/ruby && ./script/test`.
8. **Commit** proto changes and generated Ruby files together.

### Using in github/github

The `elm_exporter` gem is vendored in the Monolith (github/github). After
changes:

1. **Build the gem** from `client/ruby/` using the **system Ruby in a
   github/github codespace**:
   ```bash
   cd client/ruby
   gem build elm_exporter.gemspec
   GEM_FILE=$(ls -t elm_exporter-*.gem | head -1)
   ```
2. **Copy the gem** to the Monolith vendor cache:
   ```bash
   cp "$GEM_FILE" /workspaces/github/vendor/cache/
   rm "$GEM_FILE"
   ```
3. **Update the Gemfile** version in github/github if the version changed.
4. **Run `bin/bundle install`** in github/github to update lockfile checksums.
5. In **github/github**, **commit** the vendored `.gem` under `vendor/cache/`
   together with the `Gemfile` / `Gemfile.lock` changes.

> **CRITICAL: Gem checksums compatibility**
>
> The `.gem` file **must** be built with a RubyGems version that produces the
> legacy `checksums.yaml` format (algorithm-first keys: `SHA256`, `SHA512`,
> with a `---` YAML document marker). Newer RubyGems (e.g. 3.5.x+) produce a
> file-first format (`data.tar.gz: { SHA-256: ... }`) that CI's Ruby cannot
> verify, causing bootstrap to fail with:
> `OpenSSL::Digest::DigestError: unsupported digest algorithm`.
>
> Build the gem inside a **github/github codespace** using the system Ruby on
> `PATH` (`ruby` / `gem build`). Do **not** use the Docker `gen-ruby` image to
> produce the *vendored* gem — that path produces a different checksum format.
>
> **To verify a gem has the correct format:**
> ```bash
> tar xf /workspaces/github/vendor/cache/elm_exporter-*.gem checksums.yaml.gz
> gunzip checksums.yaml.gz && cat checksums.yaml && rm checksums.yaml
> ```
> Output **must** start with `---` and use `SHA256:` / `SHA512:` as top-level
> keys (no hyphens in the algorithm name).

## Known Open Items

- **Twirp path prefix:** the Ruby client posts to the bare
  `<package>.<Service>/<Rpc>` path (no `/twirp` prefix). Confirm this matches the
  Go server's `PathPrefix()` in `internal/pkg/twirp/server.go` against a real or
  stub server before relying on live RPCs.
- **Patched-fork load check:** verify the generated `proto3 optional` descriptor
  (`ListMigrationsRequest.status`) loads under the monolith's **patched**
  `google-protobuf 3.14` fork — local tests run against upstream 3.25.8.

## Commit Guidelines

- **DO** commit `Gemfile.lock` after running `bundle install`.
- **DO** commit generated `api_pb.rb` / `api_twirp.rb` with proto changes.
- **DO NOT** commit built gem artifacts (`elm_exporter-*.gem`) here — the
  vendored gem belongs in `github/github/vendor/cache`.
- **DO NOT** commit generator-scaffolded `Makefile`/`VERSION` files under
  `internal/proto/.../schemas`, or the `sorbet/` directory.
- **DO NOT** edit `api_pb.rb` / `api_twirp.rb` manually.\
