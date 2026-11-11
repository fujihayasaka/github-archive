# typed: true
# frozen_string_literal: true

class HydroCheckSuiteAnalysisJob < HydroMessageJob
  include GitHub::Memoizer

  class PendingCheckRunsError < StandardError; end

  retry_on_dirty_exit
  retry_on PendingCheckRunsError, delay: 30.seconds, max_retries: 10
  queue_as :hydro_check_suite_analysis

  FAILURE_CONCLUSIONS = %w[failure action_required timed_out].freeze
  MAX_FAILED_CHECK_RUNS = 50

  sig { void }
  def perform
    return unless FeatureFlag.vexi.enabled?(:validation_platform_ci_analysis_enabled, default: false)
    return unless message[:current_status] == :COMPLETED
    return unless FAILURE_CONCLUSIONS.include?(message[:conclusion])

    log("start", "gh.check_suite.conclusion" => message[:conclusion])

    # Check repository and per-repo feature flag first — repository comes
    # straight from message[:repository_id] (no DB dependency on check_suite),
    # so we can bail early for repos without the flag enabled.
    unless repository
      return log("skipping: repository not found", "gh.repository.id" => message[:repository_id])
    end

    unless FeatureFlag.vexi.enabled?(:validation_platform_ci_analysis, repository, default: false)
      return log("skipping: feature flag disabled")
    end

    unless check_suite
      return log("skipping: check_suite not found")
    end

    unless pull_request
      return log("skipping: no pull request found", "gh.pull_request.ids" => message[:pull_request_ids])
    end

    # If any check runs on this SHA are still running, raise to trigger a
    # delayed retry. The CheckSuiteStatusChange event only fires once per
    # suite completion, so we can't rely on a follow-up event when the last
    # run finishes.
    if pending_check_runs?
      log(
        "retrying: pending check runs still in progress",
        "gh.check_suite.head_sha" => message[:head_sha],
      )
      raise PendingCheckRunsError, "check runs still in progress for SHA #{message[:head_sha]}"
    end

    failed_runs = gather_failed_check_runs
    if failed_runs.empty?
      return log("skipping: no failed check runs found", "gh.check_suite.head_sha" => message[:head_sha])
    end

    log("dispatching analysis", "gh.check_runs.failed_count" => failed_runs.size)
    dispatch_analysis(failed_runs)
  end

  private

  memoize def check_suite
    CheckSuite.find_by(id: message[:check_suite_id])
  end

  memoize def repository
    Repository.find_by(id: message[:repository_id])
  end

  memoize def pull_request
    pr_ids = message[:pull_request_ids]
    return nil if pr_ids.blank?

    PullRequest.find_by(id: pr_ids.first)
  end

  def pending_check_runs?
    CheckRun
      .for_sha_and_repository_id([message[:head_sha]], repository.id)
      .where.not(status: :completed)
      .exists?
  end

  def gather_failed_check_runs
    CheckRun
      .for_sha_and_repository_id([message[:head_sha]], repository.id)
      .failed
      .limit(MAX_FAILED_CHECK_RUNS)
      .to_a
  end

  def dispatch_analysis(failed_runs)
    requestor = pull_request.user
    unless requestor
      return log("dispatch skipping: no requestor for pull request", "gh.pull_request.id" => pull_request.id)
    end

    reviewer_app = Apps::Privileged.integration(:copilot_pull_request_reviewer)
    unless reviewer_app
      return log("dispatch skipping: copilot_pull_request_reviewer integration not found")
    end

    problem_statement = build_problem_statement(failed_runs)
    event_content = build_event_content(failed_runs)

    _access, _scoped_access, capi_access = with_write do
      a = reviewer_app.grant(requestor, entry_point: :validation_platform_ci_analysis)
      unless a
        return log("dispatch skipping: failed to grant access", "gh.user.id" => requestor.id)
      end

      # If the repository owner org enforces SAML SSO, proactively create a
      # credential authorization so that convert_to_scoped_access succeeds.
      # This mirrors the pattern in CodeReviewGenerator.
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

    log("calling create_swe_agent_job", "gh.check_runs.failed_count" => failed_runs.size)

    capi.create_swe_agent_job(
      nwo: repository.full_name,
      problem_statement:,
      creation_id: SecureRandom.uuid,
      event_type: "ci_failure_analysis",
      event_content: event_content.to_json,
      skip_pull_request: true,
      skip_notification: true,
    )

    log("dispatch succeeded")
    GitHub.dogstats.increment("validation_platform.ci_analysis.dispatched", tags: ["repo:#{repository.full_name}"])
  rescue => e
    log("dispatch error: #{e.message}")
    GitHub.dogstats.increment("validation_platform.ci_analysis.dispatch_error")
    Failbot.report(e)
  end

  def build_problem_statement(failed_runs)
    run_summaries = failed_runs.map { |run| "- #{run.display_name}: #{run.conclusion} (#{run.details_url})" }.join("\n")

    <<~PROMPT
      ## Instructions

      Investigate CI check run failures on a pull request. Your goal is to perform a root cause analysis — not just list what failed, but identify WHY it failed by correlating failures with the PR diff.

      You should be given a PR or a commit. If given a PR, use the latest commit in the PR. For whichever commit you use, analyze the latest CI run. There may be multiple check runs that failed. Each check run will have logs and output that you can inspect.

      1. Analyze the PR diff and the logs/output for each failed check run in the PR. If you can, try to grep for the error rather than parsing through the whole error log. If that doesn't work, read through the logs carefully to understand the failure. Look for clues in the error messages, stack traces, and any other available output that can help you understand what went wrong and why.
      2. Group failures by the problematic diff hunk. For example, if 5 tests fail due to a single typo, report that as a single finding tied to the specific diff hunk, not 5 separate findings. However, if a method name is changed and five different tests are using the old name, that's 5 different places where the code needs to be updated, and those should each be separate findings.
      3. For each root cause finding, fill out the RawFinding type.
      4. Return an array of RawFindings ordered by the number of affected tests (most impactful first). Return ONLY the array of findings, do not include any other text in your response.

      ## Context:

      type RawFinding struct {
      ID           string `json:"id"`
      PartitionKey string `json:"partitionKey"`
      EntityType   string `json:"entityType"`

      // Source identification
      Source        string `json:"source"`        // e.g., "check_run", "code_scanning", "pr_review"
      SourceEventID string `json:"sourceEventId"` // traceability back to the originating event

      // Location
      FilePath    string `json:"filePath"`
      StartLine   int    `json:"startLine"`
      EndLine     int    `json:"endLine"`
      StartColumn int    `json:"startColumn,omitempty"`
      EndColumn   int    `json:"endColumn,omitempty"`

      // Finding content
      Message string `json:"message"`
      Title   string `json:"title,omitempty"`  // short description (e.g. check run annotation title)
      RuleID  string `json:"ruleId,omitempty"` // the source's identifier for the check/query/rule that produced this finding (e.g. "go/sql-injection" for CodeQL, "no-unused-vars" for ESLint). Empty when the source has no rule concept.

      // Source metadata — preserved as-is from the originating event
      ToolName        string `json:"toolName,omitempty"`        // producing tool, e.g. "eslint", "codeql", "copilot"; may be omitted when it would duplicate Source
      AnnotationLevel string `json:"annotationLevel,omitempty"` // source's own level hint, e.g. "notice", "warning", "failure"

      TimeIngested int64 `json:"timeIngested"`
      }

      Repository: #{repository.owner.display_login}/#{repository.name}
      PR ##{pull_request.number}: #{pull_request.title}
      Head SHA: #{message[:head_sha]}

      ## Failed check runs (#{failed_runs.size} total)

      #{run_summaries}
    PROMPT
  end

  def build_event_content(failed_runs)
    {
      check_suite_id: message[:check_suite_id],
      repository_id: repository.id,
      head_sha: message[:head_sha],
      pull_request_number: pull_request.number,
      hydro_event_timestamp: timestamp,
      failed_check_runs: failed_runs.map do |run|
        {
          id: run.id,
          name: run.display_name,
          conclusion: run.conclusion,
          status: run.status,
        }
      end,
    }
  end

  sig { params(msg: String, tags: T.untyped).void }
  def log(msg, **tags)
    base_tags = {
      "gh.check_suite.id" => message[:check_suite_id],
      "gh.job.aqueduct_id" => GitHub.context[:aqueduct_job_id],
      "gh.request_id" => GitHub.context[:request_id],
    }
    if repository
      base_tags["gh.repository.id"] = repository.id
      base_tags["gh.repository.nwo"] = repository.full_name
    end
    base_tags["gh.pull_request.number"] = pull_request.number if pull_request

    GitHub.logger.info("hydro_check_suite_analysis_job: #{msg}", **base_tags, **tags)
  end
end
