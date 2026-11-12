---
applyTo: "app/coach/**/*.rb"
---

# Coach Routes & Middleware Code Review Rules

Request handling uses **Coach** middleware-based controllers, not standard Rails controllers. Route handlers subclass `Coach::Middleware`. Examples: `app/coach/routes/ping.rb`, `app/coach/routes/update_jobs/create_pull_request.rb`, `app/coach/middlewares/check_params.rb`.

## Structure

- Route handlers use `uses SomeMiddleware` to compose auth, param-validation, and metrics middleware before the handler logic.
- Use `requires :symbol` to declare values provided by upstream middleware.
- The `call` method is the entrypoint. It must return one of the `Renderer` helpers — never use Rails-style `render`/`redirect_to`.

## Renderer (`lib/renderer.rb`)

Use the actual Renderer interface:

```ruby
Renderer.no_content                                          # 204
Renderer.render_error(status: 422, title: "...", detail: "...")  # JSON:API error
Renderer.resource(record, status: 200, serializer_options: {})
Renderer.resources(records, request:, status: 200, serializer_options: {})
```

- Do not invent new methods on `Renderer`; the four above are the supported helpers.
- Always pass `status:` for non-200 responses.

## Param validation

- Param validation should go through `CheckParams` (`app/coach/middlewares/check_params.rb`) or an equivalent middleware — not inline in the handler.
- Required params, type checks, and nested-key validation must run before the handler executes.
- Bad-input responses use `Renderer.render_error(status: 400, title: "Bad Request", ...)` — the convention in this codebase is **400** for malformed/missing-param transport errors. Reserve 422 for domain-level semantic failures.

## Read-only routes

Read-only Coach routes opt into replica routing with `uses Middlewares::ReadReplica` (see `app/coach/routes/update_jobs/record_metrics.rb`, `record_ecosystem_meta.rb`, `increment_metric.rb`). When a route declares this, scrutinize any DB writes in the handler — they will fail at runtime against the replica.

## Metrics & logging

- Metric tags emitted by middleware should be low-cardinality (route name, status code — not user IDs, request IDs, etc.).
- If a handler emits multiple log lines, consider wrapping in `Dependabot::Logger.log_context(context_hash) { ... }` for inherited context. Don't add this to handlers that emit zero or one log line.
