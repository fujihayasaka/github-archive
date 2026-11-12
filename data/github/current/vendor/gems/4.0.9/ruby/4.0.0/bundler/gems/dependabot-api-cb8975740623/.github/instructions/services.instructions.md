---
applyTo: "app/services/**/*.rb"
---

# Twirp Services Code Review Rules

Services are **Twirp** RPC handlers (`app/services/services.rb`). Reference: `app/services/update_jobs_service/v1/handler.rb`, `app/services/repositories_service/v1/handler.rb`.

## Handler structure

Handlers should be relatively thin — they validate input, look up records, and either return a response or enqueue work. Some handlers do non-trivial orchestration (`update_configs_service/v1/handler.rb`); that's acceptable when the work is bounded to the request.

If a handler grows large, propose extracting business logic into an action under `app/actions/`.

## Twirp errors

Use the explicit Twirp error helpers — never raise a generic exception or return a malformed response. The codes in active use in this codebase are:

```ruby
return Twirp::Error.not_found("repo not found", { repo_id: id })
return Twirp::Error.invalid_argument("missing or malformed field", { field: "name" })
return Twirp::Error.failed_precondition("update job is not in the right state")
return Twirp::Error.unauthenticated("...")
return Twirp::Error.internal("...")
```

Match the error code to the actual condition; don't return `invalid_argument` for a not-found resource. Follow the local convention of the surrounding service when picking between similar codes.

## Auth (`app/services/services.rb` — `Services::RackApp`)

The Twirp service rack app wraps every handler with HMAC authentication, metrics, and error reporting. Don't add per-handler auth — it's centralized.

- HMAC verification is mandatory. Never short-circuit it for "convenience".
- If a handler needs different auth (e.g., dotcom internal vs. customer), that belongs in `Services::RackApp` or in a dedicated middleware, not in the handler.

## Secrets & config

When a feature relies on a secret (HMAC key, OAuth token, etc.):

- **Fail fast** if the secret is missing or blank. Do not call out with a `nil` or empty key — the downstream error will be confusing.
- Document the env var / secret name in code (or in `script/copilot-prompts/`) and verify it is rolled out via the appropriate secrets pipeline.
- A feature flag that "enables" a code path requiring a secret should not be flippable to `true` until the secret is present in the environment.

## Response shapes

- Handlers return plain hashes that match the Twirp message type. It's OK to assemble the hash inline; serializers under `app/serializers/` are commonly used for nested objects.
- Required response fields must always be present. Optional fields should be omitted (or explicitly nil) when not applicable.
- When changing a response shape, update the protobuf definition, the serializer, and any consumer expectations in the same PR.

## Schema/validation alignment

Twirp request types, JSON schema, and model validations must agree. The cross-cutting rule is in `engineering-conventions.instructions.md`. Service-specific: a required protobuf field must be enforced in the handler with `Twirp::Error.invalid_argument`.

## Reviewer checklist

- Specific Twirp error type matches the failure mode.
- HMAC/auth happens via `Services::RackApp`, not in the handler.
- Secrets are fail-fast on blank, and feature flags are aligned with secret presence.
- Response shape change is propagated to protobuf + serializer + tests.
