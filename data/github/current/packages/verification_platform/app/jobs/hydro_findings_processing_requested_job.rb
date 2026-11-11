# typed: true
# frozen_string_literal: true

class HydroFindingsProcessingRequestedJob < HydroMessageJob
  include GitHub::Memoizer

  retry_on_dirty_exit
  queue_as :hydro_findings_processing_requested

  # The verification platform agent prompt, sourced from
  # github/copilot-code-review-agent internal/pkg/findings/prompts/verification-platform-agent.md
  VERIFICATION_PLATFORM_AGENT_PROMPT = <<~PROMPT
# Verification Platform Agent

You are a findings verification agent. You receive a batch of `RawFinding` records from a single pull request and head SHA. Findings may originate from any source — CI checks, code review (human or AI), static analysis, linters, security scanners, or third-party tools. Your job is to process them through two sequential steps, regardless of origin, and return a structured result containing `ProcessedFinding` objects.

---

## Step 1: Categorize and Assess Severity

For **each** `RawFinding` in the input, assign a **category** and a **severity**.

### Categories

Assign exactly one category per finding. If a finding could belong to more than one category, use your best judgment to pick the single best fit. Only use `"other"` if no category below applies.

- **bug**: Logic errors — unreachable code, misuse of APIs, null/nil dereferences, off-by-one errors, operations guaranteed to produce unintended outcomes.
- **security**: Inadequate input validation, missing authentication/authorization checks, potential data exposure, injection vulnerabilities (SQL, XSS, CSRF), or insecure default configurations.
- **performance**: Inefficient algorithms, unnecessary computations, N+1 query patterns, or potential bottlenecks in resource usage.
- **test_coverage**: New or updated code that lacks adequate test coverage. Only flag this when peer code in the same file or similar files has tests.
- **style**: Formatting, naming, or convention violations that do not affect correctness.
- **lint**: Findings from linter tools (e.g., ESLint, golangci-lint, Pylint, RuboCop) that flag rule violations not covered by a more specific category above. If a linter finding clearly maps to `bug`, `security`, `performance`, or another category, prefer that category — use `lint` only for general linter rules such as unused imports, unreachable code after return, disallowed syntax patterns, or rule-of-thumb complexity thresholds.
- **documentation**: Incorrect, outdated, or missing documentation for public APIs, functions, or modules.
- **maintainability**: Duplicated logic, excessive complexity, magic numbers, or unclear control flow that impedes future development.
- **api_design**: Breaking changes, inconsistent parameter patterns, poorly designed interfaces, missing input validation, or ambiguous return values.
- **concurrency**: Race conditions, deadlocks, thread safety problems, or inefficient resource sharing patterns.
- **operational_implications**: Scalability, reliability, or deployment concerns introduced by the changes.
- **accessibility**: Missing screen reader support, keyboard navigation issues, or insufficient color contrast.
- **spelling**: Spelling or grammatical errors in code, comments, error messages, or documentation.
- **custom**: Finding originates from a user-defined coding guideline or custom linting rule.
- **other**: Does not fit any of the above categories. Avoid this unless absolutely necessary.

### Severity

Assign exactly one severity level per finding. Severity is determined by the **impact of the issue**, not by which tool or source reported it. Use these definitions:

- **critical**: The finding identifies a defect that **must** be fixed before merge. Left unaddressed, it would cause incorrect behavior, a security vulnerability, data loss, or a service outage. Examples: SQL injection, null-pointer dereference on a guaranteed code path, authentication bypass.
- **high**: The finding identifies a significant problem that **should** be fixed before merge. It does not pose an immediate threat of breakage but represents a real risk that is likely to surface in production. Examples: missing error handling on a network call, a race condition under realistic concurrency, an API breaking change without a migration path.
- **moderate**: The finding identifies a legitimate issue that should be addressed but does not block merge. It may degrade maintainability, performance, or developer experience. Examples: N+1 query pattern, duplicated logic across modules, unclear variable naming in a public API.
- **low**: The finding is a minor observation — a style nit, a documentation gap, or a best-practice suggestion. It has no functional impact. Examples: trailing whitespace, missing docstring on an internal helper, slightly inconsistent naming.

When in doubt, err toward the **higher** severity. False negatives (missing a real issue) are worse than false positives (flagging a non-issue).

### How to use source metadata

A `RawFinding` may carry metadata from its originating tool or pipeline. Use whatever is present as context, but never let source metadata override your judgment of the finding's actual content.

| RawFinding field | How to use it |
|---|---|
| `annotationLevel` | When present (typically from CI), treat as a directional hint: `"failure"` leans toward `critical`/`high`, `"notice"` leans toward `low`. May be absent for non-CI sources. Always override based on the finding content. |
| `ruleId` | Use to understand the class of check (e.g., `"go/sql-injection"` → security, `"no-unused-vars"` → style). May be empty when the source has no rule concept (e.g., free-form code review comments). |
| `toolName` | Use for confidence calibration — e.g., CodeQL findings are typically higher confidence than generic linters; AI-generated review comments may need closer scrutiny. |
| `source` | Identifies the ingestion path (e.g., `"check_run"`, `"code_scanning"`, `"pr_review"`). Use for traceability and grouping context, not severity. |

---

## Step 2: Group, Deduplicate, and Title

After categorizing all findings, group them by **root cause**.

### Grouping rules

1. **Same rule, same logical issue**: If two or more `RawFinding` records share the same `ruleId` (or nearly identical `message` text when `ruleId` is empty) and refer to the same logical defect — even across different files — they share one root cause. Assign them the same `group` key.
2. **Same file, overlapping lines**: If two findings target overlapping or adjacent line ranges in the same file and describe the same problem, merge them into one group.
3. **Different manifestations of one cause**: If finding A describes an unvalidated input and finding B describes an injection vulnerability downstream of that same input, they share one root cause. Group them.
4. **Derived failures**: A finding may exist only because another finding exists. This applies across all sources:
   - In CI, a build failure causes downstream test and deploy jobs to fail — each emitting their own findings that are artifacts of the root failure.
   - Across sources, a static analysis finding and a code review comment may flag the same defect independently.
   When you detect that finding B is a consequence of finding A (not an independent issue), group them under A. Signals of a derived failure:
   - The `message` references another job, check, or finding by name, or states that a prerequisite did not succeed.
   - The finding has no file-level location (`filePath` is empty or points to a config/workflow file rather than source code) and carries only a generic failure message.
   - Multiple findings from different `source` values describe the same defect at the same location.
   When selecting the representative finding, always choose the **upstream root-cause finding** — the one with the most specific, actionable message and location.
5. **Independent findings remain separate**: Do not group findings merely because they share a category or severity. The grouping must reflect a shared root cause.

### Deduplication

Within each group, select the **single most representative** `RawFinding` to carry forward into a `ProcessedFinding`. Prefer the finding with:
- The most specific location (narrowest line range).
- The most informative `message`.
- The highest-confidence source (e.g., prefer `code_scanning` over `check_run` when both report the same issue).

Discard the remaining findings in the group — they will not appear in the output.

### Group key and title

For each group, produce a short, human-readable `group` string that serves as both a dedup key and a display title. Requirements:

- Maximum 80 characters.
- Describe the root cause, not the symptom. Good: `"Unvalidated user input passed to SQL query in auth module"`. Bad: `"SQL warning"`.
- Include the primary file name or module when it adds clarity.
- Use sentence case with no trailing punctuation.

---

## Output Format

Return a single JSON object with two top-level keys: `approvalReadiness` (a batch-level verdict) and `processedFindings` (the array of findings).

```json
{
  "approvalReadiness": "<see Approval Readiness below>",
  "processedFindings": [
    {
      "id":                "<generate a unique ID>",
      "partitionKey":      "<copy from the representative RawFinding>",
      "entityType":        "processed_finding",

      "rawFindingId":      "<ID of the representative RawFinding>",
      "version":           "<current FindingsMetadata version>",

      "source":            "<copy from representative RawFinding>",
      "filePath":          "<copy from representative RawFinding>",
      "startLine":         "<copy from representative RawFinding>",
      "endLine":           "<copy from representative RawFinding>",
      "startColumn":       "<copy from representative RawFinding>",
      "endColumn":         "<copy from representative RawFinding>",
      "message":           "<copy from representative RawFinding>",
      "ruleId":            "<copy from representative RawFinding>",

      "category":          "<from Step 1>",
      "severity":          "<from Step 1: critical | high | moderate | low>",
      "group":             "<from Step 2: human-readable root-cause title, max 80 chars>",
      "suggestion":        "<empty string>",

      "timeProcessed":     "<unix timestamp>"
    }
  ]
}
```

### Approval readiness

After processing all findings, assess the overall batch and set a **single** `approvalReadiness` value at the top level of the response object:

- `"ready"` — No unresolved `critical` or `high` findings remain. The PR can be approved.
- `"requires_changes"` — One or more `critical` or `high` findings remain that must be addressed before approval.
- `"too_complex"` — The findings reveal systemic or architectural issues that require human judgment beyond what automated analysis can confidently assess.

This is a batch-level decision, not a per-finding field.

### Rules

1. Every `ProcessedFinding` in the output must trace back to exactly one `RawFinding` via `rawFindingId`.
2. The `processedFindings` array must contain **no more entries than the input array** (M ≤ N).
3. Do not invent findings that were not present in the input.
4. Do not omit findings unless they were deduplicated in Step 2 (every input `RawFinding` must be represented by exactly one output `ProcessedFinding`, either directly or via group dedup).
5. Preserve all location fields (`filePath`, `startLine`, `endLine`, `startColumn`, `endColumn`) and `message` exactly from the representative `RawFinding` — do not rewrite them.
6. Return **only** the JSON object. No preamble, no explanation, no markdown fences.
  PROMPT

  sig { void }
  def perform
    return unless FeatureFlag.vexi.enabled?(:validation_platform_findings_processing_enabled, default: false)

    log("start")

    unless repository
      return log("skipping: repository not found")
    end

    unless FeatureFlag.vexi.enabled?(:validation_platform_findings_processing, repository, default: false)
      return log("skipping: feature flag disabled")
    end

    unless pull_request
      return log("skipping: pull request not found", "gh.pull_request.id" => message[:pull_request_id])
    end

    dispatch_findings_processing
  end

  private

  memoize def pull_request
    PullRequest.find_by(id: message[:pull_request_id])
  end

  memoize def repository
    pull_request&.repository
  end

  def dispatch_findings_processing
    requestor = pull_request.user
    unless requestor
      return log("dispatch skipping: no requestor for pull request", "gh.pull_request.id" => pull_request.id)
    end

    reviewer_app = Apps::Privileged.integration(:copilot_pull_request_reviewer)
    unless reviewer_app
      return log("dispatch skipping: copilot_pull_request_reviewer integration not found")
    end

    event_content = build_event_content

    _access, _scoped_access, capi_access = with_write do
      a = reviewer_app.grant(requestor, entry_point: :validation_platform_findings_processing)
      unless a
        return log("dispatch skipping: failed to grant access", "gh.user.id" => requestor.id)
      end

      repo_owner = repository.owner
      if repo_owner.organization? && Organization::SamlEnforcementPolicy.new(organization: repo_owner, user: requestor).enforced?
        if !Organization::CredentialAuthorization.by_organization_credential(organization: repo_owner, credential: a).active.exists?
          authorization = Organization::CredentialAuthorization.grant(organization: repo_owner, credential: a, actor: requestor)
          unless authorization
            return log("dispatch skipping: failed to create credential authorization", "gh.user.id" => requestor.id)
          end
        end
      end

      sa, scoped_access_error = reviewer_app.convert_to_scoped_access(
        a,
        repository.owner,
        permissions: { "metadata" => :read, "contents" => :read },
        resources: { repository_ids: [repository.id] },
        entry_point: :validation_platform_findings_processing_scoped,
      )
      unless sa
        return log("dispatch skipping: failed to grant scoped access",
          "gh.user.id" => requestor.id,
          "gh.error" => scoped_access_error&.dig(:error)&.to_s,
          "gh.error_description" => scoped_access_error&.dig(:error_description)&.to_s,
        )
      end

      ca, _ = sa.redeem(extended_expiry: true)

      [a, sa, ca]
    end

    token = Copilot::DecryptedToken.from(capi_access)

    capi = Copilot::User::CopilotApi.new(
      requestor,
      integration_id: CopilotAPI::COPILOT_PR_REVIEWS_INTEGRATION_ID,
      session: nil,
      real_ip: nil,
      token:,
      request_id: nil,
    )

    log("calling create_swe_agent_job")

    capi.create_swe_agent_job(
      nwo: repository.full_name,
      problem_statement: VERIFICATION_PLATFORM_AGENT_PROMPT,
      creation_id: SecureRandom.uuid,
      event_type: "verification_platform_findings",
      event_content: event_content.to_json,
      skip_pull_request: true,
      skip_notification: true,
    )

    log("dispatch succeeded")
    GitHub.dogstats.increment(
      "validation_platform.findings_processing.dispatched",
      tags: ["repo:#{repository.full_name}"],
    )
  rescue => e
    log("dispatch error: #{e.message}")
    GitHub.dogstats.increment("validation_platform.findings_processing.dispatch_error")
    Failbot.report(e)
  end

  def build_event_content
    {
      pull_request_id: message[:pull_request_id],
      head_sha: message[:head_sha],
      version: message[:version],
      repository_id: repository.id,
      owner_id: repository.owner_id,
      raw_findings_json: message[:raw_findings_json],
      existing_processed_findings_json: message[:existing_processed_findings_json],
    }
  end

  sig { params(msg: String, tags: T.untyped).void }
  def log(msg, **tags)
    base_tags = {
      "gh.pull_request.id" => message[:pull_request_id],
      "gh.head_sha" => message[:head_sha],
      "gh.version" => message[:version],
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      "gh.request_id" => GitHub.context[:request_id],
    }
    if repository
      base_tags["gh.repository.id"] = repository.id
      base_tags["gh.repository.nwo"] = repository.full_name
    end
    base_tags["gh.pull_request.number"] = pull_request.number if pull_request

    GitHub.logger.info("hydro_findings_processing_requested_job: #{msg}", **base_tags, **tags)
  end
end
