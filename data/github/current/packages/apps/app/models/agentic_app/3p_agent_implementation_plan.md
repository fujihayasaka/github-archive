# Implementation Plan Template: Privileged App & AgenticApp Adapter

_Use this checklist when introducing any new privileged agent (first-party or partner) that must surface through `AgenticApp`._

## 1. Goal

Introduce a new privileged app (placeholder: **New Agent**) and expose it via the `AgenticApp` abstraction so it participates in assignment, mention, and token provisioning workflows alongside existing agents.

## 2. Scope

- Add privileged app configuration for `Apps::Privileged::<NewAgent>` under `lib/apps/privileged/`.
- Provide test factories/helpers so integration specs can create and register the new app.
- Implement `AgenticApp::<NewAgent>` subclass that bridges the privileged app to the agent registry.
- Update registry and documentation to include the new agent and describe its enablement.
- Add unit tests mirroring existing coverage for Copilot/Claude agents.

## 3. Work Breakdown

1. **Privileged App Definition**
   - Create `lib/apps/privileged/<new_agent>.rb` defining constants (`NAME`, `SLUG`, `PRODUCTION`, `PERMISSIONS`) following the strict Sorbet pattern. Use `Apps::Privileged::ClaudeAgent` as the canonical reference for layout and capability structure.
   - Ensure `PRODUCTION` capabilities include `:is_assignable`, `:pr_autocomplete_mentionable`, and any product-specific flags; mirror additional attributes from Claude when in doubt.
   - Add `INTEGRATION_TRIGGERS` if automated installs are required; otherwise default to annotated empty array.
   - Append entries to `lib/package_todo.yml` under `::Integration` / `::IntegrationInstallTrigger` to mirror other privileged apps.

2. **Factory & Test Helpers**
   - Extend `test/factories/integration_factories.rb` with a factory (e.g., `:new_agent_integration`) that calls `PrivilegedAppHelper.reconfigure_privileged_app`.
   - Add helper methods for feature flags or enablement routines required by integration tests.

3. **AgenticApp Adapter**
   - Create `packages/apps/app/models/agentic_app/<new_agent>.rb` inheriting from `Apps::Privileged::<NewAgent>`, including `AgenticApp` + `Singleton`.
   - Implement interface methods (`slug`, `display_name`, `integration`, `bot`, `assignable?`, `mentionable?`, `global?`, `enabled_for_repository?, installed_for_target?, can_be_enabled_for?`).
   - Model enablement strategy after the agent’s deployment model (global vs installation, feature flags, rollout guards).

4. **Agent Runtime Feature Flag**
   - Introduce a viewer-scoped Vexi flag following the pattern `copilot_swe_agent_runtime_entry_point_<new_agent_slug>` to gate runtime access.
   - Add tests (or extend helpers) that enable/disable this flag for the viewer to validate `enabled_for_repository?` behavior.
   - Document how to flip the flag for dogfooding and production rollout.

5. **Registry Update**
   - Update `AgenticApp.default_registry` to include the new agent instance in the desired order.
   - Ensure order is logical (e.g., Copilot, Claude, Codex).

6. **Tests**
- Add assertions to `test/lib/apps/agentic_app_test.rb` verifying the new agent responds to expected interface methods.
- Create focused tests covering enablement logic if it differs from existing agents.

## 4. Risks & Mitigations

- **Packwerk Violations**: ensure `lib/package_todo.yml` entries are added at creation to avoid packwerk failures.
- **Feature Flag Gating**: confirm enablement respects existing flags or introduce a new one to avoid premature exposure.
- **Registry Duplication**: avoid memoizing integrations so tests that swap apps stay consistent (follow current Copilot/Claude approach).

## 5. Validation

- `bin/rails test test/lib/apps/agentic_app_test.rb`
- Any new agent-specific tests introduced in helper modules or assignment flows.
- `bin/rubocop lib/apps/privileged/<new_agent>.rb packages/apps/app/models/agentic_app/<new_agent>.rb`
- Optional: targeted Packwerk (`bin/packwerk check lib/apps/privileged/codex_agent.rb`) to confirm TODO entries cover references.

---

Once the above tasks are complete and validated, proceed to implement the new privileged app and companion AgenticApp adapter.
