---
name: test-runtime-pr-in-staging
description: Create a sweagentd PR to test a copilot-agent-runtime PR in staging. Use this skill whenever asked to deploy, test, or try out a runtime PR in staging, or to create a staging test PR for a runtime change.
---

# Test a copilot-agent-runtime PR in staging

You are helping the user create a sweagentd PR that points the `runtime` submodule at a copilot-agent-runtime PR branch so it can be tested in staging.

## Inputs

Ask the user for:

1. **The runtime PR** — a URL like `https://github.com/github/copilot-agent-runtime/pull/<number>` or just a PR number.
2. **Whether a feature flag needs to be passed through** — if yes, ask for the flag name.

## Procedure

### 1. Fetch the runtime PR details

Use the GitHub MCP tools to read the PR and extract:
- The **PR title**
- The **head branch name**
- The **PR URL**
- A **brief description** of the changes (from the PR body)

### 2. Create a new branch

From the repo root on `main` (pull latest first):

```
git checkout main && git pull
git checkout -b <user>/<descriptive-branch-name>
```

Use a branch name derived from the runtime PR (e.g. `timrogers/test-fix-duplicate-mcp-tool-names`).

### 3. Update the runtime submodule

```
cd runtime/
gh pr checkout <pr-number>
cd ..
```

### 4. (Optional) Add a feature flag

If the user needs a feature flag passed through to the runtime, add it to `internal/launcher/runtime_feature_flags.go`.

- Add the flag name to the `enabledViaAny` list in the `runtimeFeatureFlags` var. Prefer a string literal; if the list already uses a `featureflags.<Const>` for the same flag, follow that existing pattern instead.
- Add the new entry near similar flags in the list. Do **not** reorder or resort the entire list just to make it alphabetical; keep changes minimal.
- After editing Go files, run `make format` and `script/lint` to ensure the change is clean.

### 5. Commit

Create a single commit (or two if there's a feature flag change) with this title format:

```
[DO NOT MERGE] Test "<original runtime PR title>" in staging
```

Always include the co-author trailer:

```
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

⚠️ **Shell escaping warning**: The runtime PR title often contains double quotes or other special characters. To avoid mangled escaping in commit messages and PR titles:
- For `git commit -m`, use single quotes around the message to avoid shell interpretation of double quotes. If the message itself contains single quotes, use `$'...'` syntax or heredoc.
- For `gh pr create --title`, likewise use single quotes to wrap the title.
- **Never escape inner quotes with backslashes** — this causes literal `\"` to appear in the title.
- After committing, verify the message looks correct with `git log -1 --format="%s"`.

### 6. Push and create the PR

Push the branch and create a PR with:

- **Title**: `[DO NOT MERGE] Test "<original runtime PR title>" in staging`
- **Body**:
  ```
  This updates the runtime submodule to <runtime PR URL> to test <brief description of what the runtime PR does>.
  ```
- **Base branch**: `main`

### 7. Report back

Share the created PR URL with the user.
