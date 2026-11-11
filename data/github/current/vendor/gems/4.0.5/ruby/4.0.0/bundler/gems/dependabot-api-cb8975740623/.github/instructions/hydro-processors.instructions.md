---
applyTo: "app/hydro/**/*.rb,app/processors/**/*.rb"
---

# Hydro Events & Processors Code Review Rules

Hydro is the event-streaming pipeline. Processors subscribe to topics; handlers do the work. Reference: `app/processors/application_processor.rb`, `app/processors/repository_push_processor.rb`, `app/hydro/github_action_compute_usage_handler.rb`.

## Processors (`app/processors/`)

- Inherit from `ApplicationProcessor` (which extends `Hydro::Processor`).
- Define `group_name <name>` — used to build the Kafka consumer group ID `dependabot_api_<name>`.
- Use `handle_topic(pattern, handler_class)` to wire the topic to a handler.
- Do **not** implement business logic in the processor itself — delegate to a handler class under `app/hydro/`.

## Handlers (`app/hydro/`)

- Expose `self.run(message)` (called by the processor) and an instance `run` method.
- **Guard early** against irrelevant messages — check payload fields (action, sender, type) at the top of `run` and return before doing any work.
- Bounded inline work is acceptable: lookups, atomic updates, filtering, and small DB reads/writes (see `app/hydro/repository_push_handler.rb`, `app/hydro/vulnerability_updates_enabled_handler.rb`). What handlers should **not** do inline is fan-out, long-running operations, or anything that could exceed a few hundred milliseconds — that work belongs in a job.
- Some handlers explicitly use `ActiveRecord::Base.connected_to(role: :reading|:writing)` to route between primary and replicas (see `repository_push_handler.rb`); others do DB work without an explicit block. Both patterns are valid. The rule: **when the surrounding code already uses `connected_to(:reading)`, mutations inside that block will fail** — flag them.
- Log receipt of relevant messages using `Dependabot::Logger.info(msg: ..., **context)` so we can trace event flow.

## DB role safety inside `connected_to` blocks

When a handler explicitly opens an `ActiveRecord::Base.connected_to(role: :reading)` block, every `update!`, `create!`, `destroy`, `delete_all`, etc. inside that block will raise at runtime. Read-then-write patterns should split into a `:reading` lookup followed by a `:writing` mutation. Don't introduce mutations into an existing `:reading` block.

## Dead-letter errors (CRITICAL)

`ApplicationProcessor::DEAD_LETTER_ERRORS` lists exception classes that cause a message to be discarded instead of retried. When reviewing additions to this list:

1. **Use the narrowest possible error class.** Never add generic classes like `ArgumentError`, `StandardError`, or `ActiveRecord::RecordNotFound` — they could occur in any processor and silently drop messages.
2. **If you need to discard a specific failure mode, raise a distinct error class as close to the source as possible** (in the affected processor/handler), then dead-letter that specific class.
3. **Each entry is a hash mapping the error class to a boolean** indicating whether to report it to the error tracker. Default to `true` unless the error is truly noisy and benign.
4. **Document the reason** in a comment above the entry — what message causes it, and why dropping is correct.

## Multi-topic subscription (enterprise / development)

`ApplicationProcessor.handle_topic` automatically registers the handler with `MultiTopicProcessor.multi_subscribe` when `Dependabot.enterprise?` or `Rails.env.development?` (see `app/processors/application_processor.rb:42` and `app/processors/multi_topic_processor.rb`). In enterprise/dev, a single consumer process runs all subscriptions; in production cloud, each processor is its own consumer.

What this means for review:

- **Don't** call `MultiTopicProcessor.multi_subscribe` directly from a processor — `handle_topic` does it for you. Direct calls would bypass the production subscription path.
- New processors should still use the standard `group_name` + `handle_topic` pattern; that single declaration covers both deployment modes.

## Reviewer checklist

- Handlers guard irrelevant messages before any work.
- DB access is wrapped in the correct `connected_to(role:)` block; mutations don't appear inside `:reading` blocks.
- Long-running or fan-out work is delegated to jobs, not done inline.
- New `DEAD_LETTER_ERRORS` entries are narrow, justified in a comment, and have explicit error-reporting behavior.
- New processors have a `group_name` and a `handle_topic` declaration.
- Use shared examples from `spec/processors/shared_examples/application_processor.rb` when adding processor specs.
