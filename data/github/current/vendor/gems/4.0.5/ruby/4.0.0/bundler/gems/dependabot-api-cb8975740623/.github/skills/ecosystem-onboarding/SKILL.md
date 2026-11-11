---
name: ecosystem-onboarding
description: >
  Onboard a new package ecosystem to dependabot-api. Use this skill when asked to add a new ecosystem,
  onboard a package manager, or register a new language ecosystem for Dependabot. This skill automates
  the rake task execution and guides through the manual follow-up steps required to fully onboard an ecosystem.
---

# Ecosystem Onboarding Skill

This skill onboards a new package ecosystem to dependabot-api. It uses the existing `rake ecosystem:onboard`
task for the automated parts, then completes the manual follow-up steps.

## Prerequisites

Before starting, gather the following information:
- **Ecosystem name** (required): The name as it appears in dependabot.yml config files (e.g., "deno", "conda", "helm")
- **Package manager name** (optional): If different from ecosystem name (e.g., "npm_and_yarn" for the "npm" ecosystem)
- **File patterns**: The manifest and lockfile patterns the ecosystem uses (e.g., `deno.json`, `deno.lock`)
- **Language mapping**: Which language constant to map to in `Ecosystems::PACKAGE_MANAGER_LANGUAGE_MAPPING`
- **Lockfiles** (if applicable): The lockfile names for `PACKAGE_MANAGERS_WITH_LOCKFILES` in `app/models/update_config.rb`

## Feature Flagging

New ecosystems are beta-gated via `enable-beta-ecosystems: true` in the user's `dependabot.yml`. The rake task
adds the ecosystem to `Ecosystems::BETA` which activates this gating automatically.

**Do NOT** add entries to `PERMITTED_REPO_FEATURES` in `app/controllers/concerns/chatop_repo_features.rb` — that is the deprecated
Flipper-based approach. If an additional internal kill-switch is needed, use a monolith feature flag
(`monolith_feature_enabled?`) configured in `github/github`.

## Step 1: Run the Onboarding Rake Task

Run the automated onboarding task inside the Docker container:

```bash
script/app-env rake "ecosystem:onboard[<ecosystem_name>,<package_manager_name>,overwrite]"
```

If `package_manager_name` is the same as `ecosystem_name`, pass an empty second argument:

```bash
script/app-env rake "ecosystem:onboard[<ecosystem_name>,,overwrite]"
```

This automates:
- Adding the ecosystem to the protobuf `PackageEcosystem.Name` enum with the next available ID
- Adding `PackageManagers::<ECOSYSTEM>` to the `Ecosystems::BETA` array in `lib/ecosystems.rb`
- Adding a `<ecosystem>_regex` method stub to `lib/ecosystem_file_regex.rb`
- Adding the ecosystem to `PACKAGE_MANAGER_LOOKUP` in `app/actions/parse_config_file.rb`
- Adding the ecosystem to the JSON config schema in `config/config_file_json_schema.json`

## Step 2: Update File Regex Patterns

Edit `lib/ecosystem_file_regex.rb` and replace the TODO placeholder in the generated `<ecosystem>_regex` method
with the actual file patterns for the ecosystem. Use existing methods as a reference for the pattern format.

Example for Deno:
```ruby
def deno_regex
  /(?:^|\/)(deno\.jsonc?|deno\.lock)$/
end
```

## Step 3: Add Language Mapping

In `lib/ecosystems.rb`, add an entry to `PACKAGE_MANAGER_LANGUAGE_MAPPING`:

```ruby
PackageManagers::<ECOSYSTEM> => Languages::<LANGUAGE>,
```

Look at existing mappings for reference. Choose the closest language constant (e.g., `Languages::JAVASCRIPT` for Deno/Bun).

## Step 4: Add Lockfile Mapping (if applicable)

If the ecosystem uses lockfiles, add an entry to `PACKAGE_MANAGERS_WITH_LOCKFILES` in `app/models/update_config.rb`:

```ruby
PackageManagers::<ECOSYSTEM> => %w(<lockfile_names>),
```

## Step 5: Regenerate Protobuf Code

Run the protobuf code generator to produce the updated Ruby Twirp files:

```bash
script/protoc
```

This regenerates files in `gen/ruby/`.

## Step 6: Bump Proto Gem Version

Update the version in `gen/ruby/lib/proto/dependabot-api/version.rb`. Bump the gem version per the repo's convention.

## Step 7: Run Tests

Run the full test suite to ensure nothing is broken:

```bash
script/test
```

If specific test files fail, investigate and fix. Common issues:
- Missing factory definitions
- Schema validation failures in config file tests
- Protobuf enum mismatches

## Step 8: Run Linter

Ensure no linting violations:

```bash
script/lint
```

## Step 9: Commit Changes

Commit all changes with a descriptive message referencing the issue.

## Reference

- Documentation: `docs/ecosystem-onboarding.md`
- Rake task: `lib/tasks/ecosystem_onboarding.rake`
- Onboarding logic: `lib/ecosystem_onboarding.rb` and `lib/ecosystem_onboarding/*.rb`
- Example ecosystems to reference: look at recent additions like `conda`, `julia`, `helm` in the codebase
