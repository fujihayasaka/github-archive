---
applyTo: "**"
excludeAgent: "cloud-agent"
---

# Code Review Style (Review-Only)

These rules are for Copilot code review specifically — they are excluded from the cloud agent because they describe how to review, not what to write.

## PR description completeness

The author-facing rules for filling in the PR template live in `.github/copilot-instructions.md` ("Pull Request Descriptions"). The reviewer's job is to spot mismatches and gaps:

- Flag exactly-one-of-N checklists (Risk Assessment, Is there a Feature Flag?) where zero or more than one box is checked.
- Don't be pedantic about prose length — a brief but real answer is fine. Leftover `<!-- ... -->` placeholder comments around a real answer are not worth flagging.

## PR description vs. code reality

Cross-check what the description claims against what the diff actually does:

- If the "Is there a Feature Flag?" checklist is marked **No** but the diff calls `monolith_feature_enabled?(...)`, flag the mismatch and ask for the flag name and rollback path.
- If the description names a flag, it should match the symbol passed to `monolith_feature_enabled?` in the diff.
- For production-targeted PRs that exclude proxima or GHES, the description should explain why.

## What to skip — keep the noise low

Don't comment on:

- Style/formatting that RuboCop catches (unless a `rubocop:disable` is being added without justification).
- Whitespace, import ordering, trailing commas.
- Subjective preferences with no codebase precedent.
- Praise/acknowledgement comments.
- Tests that lack `# typed:` sigils — Sorbet adoption in this repo is sparse and not required outside specific files.

## Comment quality

- Each comment should reference a specific line and explain both the issue and a fix.
- Don't speculate about changes. If you're unsure, phrase as a question, not a finding.
- Don't repeat the same finding across multiple lines — make one summary comment.
