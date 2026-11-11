# typed: true
# frozen_string_literal: true

class HydroCheckRunAnalysisJob < HydroMessageJob
  include GitHub::Memoizer

  retry_on_dirty_exit
  queue_as :hydro_check_run_analysis

  FAILURE_CONCLUSIONS = %i[FAILURE ACTION_REQUIRED TIMED_OUT].freeze
  LOCK_TTL = T.let(5.minutes.to_i, Integer)
  LOCK_KEY = "HydroCheckRunAnalysisJob_%{check_run_id}"

  sig { void }
  def perform
    return unless message[:current_status] == :COMPLETED
    return unless FAILURE_CONCLUSIONS.include?(message[:current_conclusion])

    log("start", "gh.check_run.conclusion" => message[:current_conclusion])

    unless check_run
      return log("skipping: check_run not found", "gh.check_run.id" => message[:check_run_id])
    end

    unless repository
      return log("skipping: repository not found")
    end

    unless FeatureFlag.vexi.enabled?(:validation_platform_ci_analysis_check_runs_enabled, repository, default: false)
      return log("skipping: check_runs feature flag disabled")
    end

    unless pull_request
      return log("skipping: no pull request found")
    end

    log("dispatching analysis", "gh.check_run.id" => check_run.id)

    lock_key = LOCK_KEY % { check_run_id: check_run.id }
    GitHub::Restraint.new.lock!(lock_key, 1, LOCK_TTL) do
      dispatch_analysis
    end
  rescue GitHub::Restraint::UnableToLock
    log("skipping: duplicate job detected", "gh.check_run.id" => check_run.id)
  end

  private

  memoize def check_run
    CheckRun.find_by(id: message[:check_run_id])
  end

  memoize def repository
    check_run&.repository
  end

  memoize def pull_request
    head_sha = check_run&.check_suite&.head_sha
    return nil unless head_sha
    return nil unless repository

    PullRequests.domain.find_open_pull_request_by_head_sha(repository, head_sha: head_sha)
  end

  def dispatch_analysis
    requestor = pull_request.user
    unless requestor
      return log("dispatch skipping: no requestor for pull request", "gh.pull_request.id" => pull_request.id)
    end

    reviewer_app = Apps::Privileged.integration(:copilot_pull_request_reviewer)
    unless reviewer_app
      return log("dispatch skipping: copilot_pull_request_reviewer integration not found")
    end

    problem_statement = build_problem_statement
    event_content = build_event_content

    _access, _scoped_access, capi_access = with_write do
      a = reviewer_app.grant(requestor, entry_point: :validation_platform_ci_analysis)
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
        entry_point: :validation_platform_ci_analysis_scoped,
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

    log("calling create_swe_agent_job", "gh.check_run.id" => check_run.id)

    capi.create_swe_agent_job(
      nwo: repository.full_name,
      problem_statement:,
      creation_id: SecureRandom.uuid,
      event_type: "ci_check_run_failure_analysis",
      event_content: event_content.to_json,
      skip_pull_request: true,
      skip_notification: true,
      base_ref: pull_request.base_ref,
    )

    log("dispatch succeeded")
    GitHub.dogstats.increment("validation_platform.ci_analysis.check_run.dispatched", tags: ["repo:#{repository.full_name}"])
  rescue => e
    log("dispatch error: #{e.message}")
    GitHub.dogstats.increment("validation_platform.ci_analysis.check_run.dispatch_error")
    Failbot.report(e)
  end

  def build_problem_statement
    <<~PROMPT
      ## Instructions

      You've been given a single failed check run on a pull request. Your goal is to perform a root cause analysis — not just describe what failed, but identify WHY it failed by correlating the failure with the PR diff.

      Do the following:
      1. Analyze the PR diff and the logs/output for this check run. If you can, try to grep for the error rather than parsing through the whole error log. If that doesn't work, read through the logs carefully to understand the failure. Look for clues in the error messages, stack traces, and any other available output that can help you understand what went wrong and why.
      2. Identify the root cause(s) of the failure. These might be a specific line of code that was changed, a missing dependency, a configuration issue, a problem or conflict with the upstream branch, or something else. It could be one thing or multiple things. Be as specific as possible in identifying the root causes.
      3. If the root cause is due to an issue with the pull request code, work on a fix and test it out to verify it will fully resolve the issue. Once you have the fix(es), include the suggested code change(s) in the form of a unified diff hunk. If the fix is more complex or involves significant restructuring, provide a high-level description of the necessary changes and omit the FixDiffHunks.

      Return an array of Findings ordered by the FixType ('code_change', then 'merge_main', then 'retry'). Return ONLY the array of findings, do not include any other text in your response. DO NOT push any code to the pull request; your job is only to analyze and return the list of Finding(s).

      ## Context


      type Finding struct {
      PartitionKey string `json:"partitionKey"`
      EntityType   string `json:"entityType"`

      // --- Source identification ---

      Source        string `json:"source"`
      SourceEventID string `json:"sourceEventId"`

      // --- Location (nullable — not all CI findings map to a specific code location) ---

      FilePath    string `json:"filePath,omitempty"`
      StartLine   *int   `json:"startLine,omitempty"`
      EndLine     *int   `json:"endLine,omitempty"`
      StartColumn *int   `json:"startColumn,omitempty"`
      EndColumn   *int   `json:"endColumn,omitempty"`

      // --- Finding content ---

      Message string `json:"message,omitempty"`
      Title   string `json:"title,omitempty"`
      RuleID  string `json:"ruleId,omitempty"`

      // --- Source metadata ---

      ToolName        string `json:"toolName,omitempty"`
      AnnotationLevel string `json:"annotationLevel,omitempty"`
      TimeIngested int64 `json:"timeIngested"`

      // --- CI-specific fix metadata ---

      // Category classifies the CI failure, e.g. "build_failure", "test_failure", "lint".
      Category string `json:"category,omitempty"`

      // FixType indicates how the CI failure should be resolved.
      // Possible values:
      //   "code_change"    — the PR introduced a bug or missing update that requires code changes to fix
      //   "merge_main"     — the failure is caused by the branch being out of date; merging the main branch should resolve it
      //   "retry"          — the failure is flaky or transient; retrying the CheckRun should resolve it
      FixType string `json:"fixType"`

      // FixDiffHunks is an optional array of diff hunks representing code changes
      // that would fix the CI failure. Only populate when FixType is "code_change"
      // and you can produce a concrete fix. Omit or leave null for "merge_main"
      // and "retry" fix types. Multiple hunks may target different files or
      // non-contiguous ranges within the same file.
      FixDiffHunks []FixDiffHunk `json:"fixDiffHunks,omitempty"`

      FailedCheckRunID         int64  `json:"failedCheckRunId"`
      FailedCheckRunName       string `json:"failedCheckRunName"`
      FailedCheckRunConclusion string `json:"failedCheckRunConclusion,omitempty"`
      }

      // FixDiffHunk represents a single unified diff hunk for a code fix.
      type FixDiffHunk struct {
      // FilePath is the repository-relative path of the file to change (e.g. "src/app.rb").
      FilePath string `json:"filePath"`

      // StartLine is the 1-based line number in the original file where the change begins.
      StartLine int `json:"startLine"`

      // EndLine is the 1-based line number in the original file where the change ends (inclusive).
      EndLine int `json:"endLine"`

      // Suggestion is the replacement text between StartLine and EndLine — the "+" lines
      // extracted from Diff, matching the GitHub ```suggestion block format.
      Suggestion string `json:"suggestion,omitempty"`
      }

      Repository: #{repository.owner.display_login}/#{repository.name}
      PR ##{pull_request.number}: #{pull_request.title}
      Head SHA: #{check_run.head_sha}

      ## Failed check run

      - #{check_run.display_name}: #{check_run.conclusion} (#{check_run.details_url})
    PROMPT
  end

  def build_event_content
    {
      check_run_id: check_run.id,
      check_suite_id: check_run.check_suite_id,
      repository_id: repository.id,
      head_sha: check_run.head_sha,
      pull_request_number: pull_request.number,
      hydro_event_timestamp: timestamp,
      failed_check_run: {
        id: check_run.id,
        name: check_run.display_name,
        conclusion: check_run.conclusion,
        status: check_run.status,
      },
    }
  end

  sig { params(msg: String, tags: T.untyped).void }
  def log(msg, **tags)
    base_tags = {
      "gh.check_run.id" => message[:check_run_id],
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      "gh.request_id" => GitHub.context[:request_id],
    }
    if repository
      base_tags["gh.repository.id"] = repository.id
      base_tags["gh.repository.nwo"] = repository.full_name
    end
    base_tags["gh.pull_request.number"] = pull_request.number if pull_request

    GitHub.logger.info("hydro_check_run_analysis_job: #{msg}", **base_tags, **tags)
  end
end
