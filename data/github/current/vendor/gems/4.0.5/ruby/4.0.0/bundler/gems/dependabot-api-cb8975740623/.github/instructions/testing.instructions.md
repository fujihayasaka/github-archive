---
applyTo: "spec/**/*.rb"
---

# Testing Code Review Rules

Tests use **RSpec** with **FactoryBot** and **VCR**. Reference: `spec/spec_helper.rb`, `spec/rails_helper.rb`.

## Coverage expectations

New behavior — including new metrics, log lines, branches, and feature-flag gates — needs spec coverage. Reviewers consistently ask for:

- A test for every new branch (especially metric/log conditional emission).
- An assertion in **both** the success and failure examples when a new metric is emitted on both paths (PR #8155 missed this).
- An assertion that a follow-up job was enqueued, when the action's job is the side effect being tested.
- For feature-flag-gated code: tests for both `enabled: true` and `enabled: false`.

## MetricsClient stubbing (CRITICAL — Copilot has missed this)

**`MetricsClient` is pre-stubbed with `and_call_original`** for the following methods in `spec/spec_helper.rb`:

```
timing, time, increment, count, gauge, distribution, histogram, distribution_time
```

This means you can call `expect(MetricsClient).to have_received(:foo)` after the fact without re-stubbing. **However**, if you write:

```ruby
expect(MetricsClient).to receive(:distribution_time)  # ❌ replaces the stub, block won't yield
```

…you replace the global stub and the **block passed to `distribution_time` (or `time`/`timing`) will not execute**. Since jobs commonly wrap their core logic in `MetricsClient.distribution_time { ... }`, this can cause the test to assert nothing happens because the work itself was skipped.

Use one of these instead:

```ruby
# Best: assert after the fact (the global stub already calls original)
expect(MetricsClient).to have_received(:distribution_time).with(...)

# Or explicitly call original / yield:
expect(MetricsClient).to receive(:distribution_time).and_call_original
expect(MetricsClient).to receive(:distribution_time) { |_name, &block| block.call }
```

This is one of the most common bugs Copilot misses — flag any `expect(MetricsClient).to receive(...)` that is timing/distribution-style and doesn't call original or yield.

## Feature flag stubbing

Use the helpers from `spec/support/monolith_feature_flag_helper.rb`:

```ruby
stub_monolith_feature(:dependabot_my_feature, actor: repo.monolith_actor, enabled: true)
stub_monolith_feature(:dependabot_my_feature, actor: nil, enabled: false)  # global
stub_monolith_error(:dependabot_my_feature)  # simulate a flag-lookup failure
```

Signatures:

- `stub_monolith_feature(feature, actor: nil, use_cache: true, enabled: true)`
- `stub_monolith_error(feature, actor: nil, use_cache: true)`

Prefer `stub_monolith_feature` over a bare `allow(Dependabot::Application).to receive(:monolith_feature_enabled?).and_return(...)` — the helper matches the real lookup path. It is acceptable to use `.and_call_original` together with `stub_monolith_feature` calls when a spec needs both real lookups and a few stubbed flags (see `spec/hydro/vulnerability_alert_handler_spec.rb`).

## Environment-scoped tests

`spec/spec_helper.rb` defines metadata-tag filters:

```ruby
it "does something enterprise-only", enterprise: true do ... end       # only when Dependabot.enterprise?
it "does something proxima-only", proxima: true do ... end             # only when Dependabot.proxima?
it "skips in proxima", proxima: false do ... end                       # skipped when Dependabot.proxima?
it "does something cloud-only", cloud: true do ... end                 # skipped in enterprise OR proxima
```

When adding behavior gated to one environment, mark its specs with the right tag.

## Factories & VCR

- Factories live in `spec/factories/`. Use traits to encode valid state transitions (`create(:update_job, :failed)`), not helper methods.
- VCR cassettes live in `spec/fixtures/vcr_cassettes/`. Re-record with `VCR=all DEPENDABOT_TEST_ACCESS_TOKEN=<token> script/test spec/path/to_spec.rb`. Sensitive headers are auto-filtered via `spec_helper.rb` — don't disable that.

## Shared examples & contexts

Use `spec/processors/shared_examples/application_processor.rb` for processor specs. Use `RSpec.shared_context "chatops controller"` and `"internal twirp api"` for those request types.

## Reviewer checklist

- New code paths have specs (both success and failure).
- `expect(MetricsClient).to receive(:timing|time|distribution_time)` calls `.and_call_original` or yields the block.
- Feature-flag-gated behavior has tests for both states using `stub_monolith_feature`.
- Side-effect assertions (enqueued jobs, log calls, metrics) match the actual production behavior.
- Test names accurately describe what's being asserted.
