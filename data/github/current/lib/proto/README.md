# Protocol Buffers (dotcom)

This directory holds the `.proto` sources used by the monolith and their
generated Ruby bindings. Protos are primarily used to define response payloads
that are rendered as proto3-JSON (see
`ApplicationController::ProtoJsonDependency#render_proto_json`) and shared with
downstream consumers such as github-ui.

## Layout

```
lib/proto/<package>/<version>/<name>.proto      # source
lib/proto/<package>/<version>/<name>_pb.rb       # generated Ruby bindings (committed)
```

- `lib/proto` is on `$LOAD_PATH` (see `config/basic.rb`), so cross-proto imports
  and consumers resolve via `require "<package>/<version>/<name>_pb"`.
- The directory tree mirrors each file's `package` namespace.
- `buf.yaml` declares `lib/proto` as the only module so downstream consumers can
  run `buf export` against this repo.

## Creating a new proto

1. Create `lib/proto/<package>/<version>/<name>.proto`.
2. Use `proto3` syntax and the conventional `github.<package>.<version>`
   package name. Including the `github.` prefix keeps the generated message
   `$typeName` strings namespaced for cross-repo clarity.

   ```proto
   syntax = "proto3";

   package github.pull_requests.v1;

   import "google/protobuf/wrappers.proto";

   message DiffstatResponse {
     Diffstat diffstat = 1;
   }

   message Diffstat {
     google.protobuf.Int32Value lines_added = 1;
     google.protobuf.Int32Value lines_deleted = 2;
     google.protobuf.Int32Value lines_changed = 3;
   }
   ```

3. Add a SERVICEOWNERS entry for the new `.proto` and `_pb.rb` files (the
   `lib/proto/<package>/` tree may already have an owning rule), then run
   `bin/generate-service-files.rb`.

## Generating the Ruby bindings

Run:

```sh
bin/generate-proto-dotcom
```

This regenerates the committed `*_pb.rb` bindings for every `.proto` under
`lib/proto/`. On first run it downloads a pinned `protoc` (matching the
`google-protobuf` gem version in `Gemfile.lock`) into `tmp/protoc/`.

While iterating you can watch for changes:

```sh
bin/generate-proto-dotcom --watch
```

Commit the regenerated `*_pb.rb` files alongside the `.proto` change.

## Updating Sorbet types

Sorbet RBIs are produced separately from the Ruby bindings. `sorbet/config`
ignores `/lib/proto/`, so Sorbet reads the generated RBIs instead of the
`_pb.rb` files. After generating or changing bindings, run:

```sh
bin/tapioca dsl
```

## Guidance

### When to use Google wrapper types

Plain proto3 scalar fields (`int32`, `string`, `bool`, ...) cannot distinguish
"unset" from their zero value (`0`, `""`, `false`), and proto3-JSON serializes a
zero-value scalar and an unset scalar identically. Use the
`google.protobuf` wrapper types (`Int32Value`, `StringValue`, `BoolValue`, ...)
when the client must be able to tell **absent / `null`** apart from the zero
value.

Typical cases:

- A value that is genuinely optional and whose absence is meaningful.
- A field the server may render as `null` (e.g. when an upstream call fails and
  the controller rescues the error and renders `nil`). See
  `lib/proto/pull_requests/v1/diffstat.proto`.

If the zero value is always a valid, unambiguous answer, prefer a plain scalar.

To use a wrapper, `import "google/protobuf/wrappers.proto";` and declare the
field as e.g. `google.protobuf.Int32Value`.

### Wrapper helpers

Constructing wrapper messages by hand is repetitive and has to special-case
`nil`. Use `GitHub::Protobuf::Wrappers` (in
[`lib/github/protobuf/wrappers.rb`](../github/protobuf/wrappers.rb)) instead. Each
helper returns `nil` for a `nil` input so the field is left unset on the
message:

```ruby
Github::PullRequests::V1::Diffstat.new(
  lines_added:   GitHub::Protobuf::Wrappers.int32_value(lines_added),
  lines_deleted: GitHub::Protobuf::Wrappers.int32_value(lines_deleted),
  lines_changed: GitHub::Protobuf::Wrappers.int32_value(lines_changed),
)
```

Available helpers: `str_value`, `int32_value`, and `bool_value`. Add more there
if you need other wrapper types.
