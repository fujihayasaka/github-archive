# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class CreateCodeScanningAnnotationsJob < ApplicationJob
  resolve_tenant_context do |args|
    repository = CheckRun.find_by(id: args[:check_run_id])&.repository
    Business.find(repository.tenant_id) if repository.present?
  end

  queue_as :code_scanning

  attr_reader :annotation_creator

  use_primaries ApplicationRecord::RepositoriesActionsChecks, ApplicationRecord::IssuesPullRequests

  use_replicas ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Permissions,
    ApplicationRecord::Spokes

  before_perform do |job|
    context = { job: job.class.name }
    args = job.arguments.first
    context = context.merge(args) if args && args.is_a?(Hash)
    Failbot.push(context)

    @annotation_creator = CodeScanning::AnnotationCreator.new
  end

  retry_on ActiveRecord::RecordNotFound, wait: :polynomially_longer do |job, error|
    # This logging/erroring is because we previously had a retry loop before calling this job due to a race condition
    # As the active job will retry on its own this logging can most likely be removed once we establish that these jobs complete
    GitHub.logger.error(
      "Record not found",
      "code.namespace" => "CreateCodeScanningAnnotationsJob",
      "code.function" => "perform",
      "gh.check_run.id" => job.check_run_id,
    )
    Failbot.report(error)
  end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  retry_on CodeScanning::PullRequestAlerts::RetriableTurboscanError, wait: :polynomially_longer do |job, error|
    GitHub.logger.error(
      "Marking job as timed out due to Turboscan Error",
      "code.namespace" => "CreateCodeScanningAnnotationsJob",
      "code.function" => "perform",
      "gh.check_run.id" => job.check_run_id,
    )
    Failbot.report(error, "gh.check_run.id": job.check_run_id, "gh.repo.id": error&.repo_id, "gh.turboscan.twirp_error_code": error&.twirp_error&.to_s)
    job.mark_check_run_timed_out
  end

  discard_on CodeScanning::PullRequestAlerts::NotFoundError do |job, _error|
    GitHub.logger.error(
      "Marking job as neutral due to Turboscan 404 response",
      "code.namespace" => "CreateCodeScanningAnnotationsJob",
      "code.function" => "perform",
      "gh.check_run.id" => job.check_run_id,
    )
    job.mark_check_run_neutral
  end

  retry_on GitHub::Restraint::UnableToLock, wait: 1.minute, attempts: 10 do |job, error|
    GitHub.logger.error(
      "Marking job as timed out due to UnableToLock",
      "code.namespace" => "CreateCodeScanningAnnotationsJob",
      "code.function" => "perform",
      "gh.check_run.id" => job.check_run_id,
    )
    Failbot.report(error, "gh.check_run.id": job.check_run_id)
    job.mark_check_run_timed_out
  end

  CheckRunOrSuiteNotFoundError = Class.new(StandardError)
  CheckRunNotFoundError = Class.new(CheckRunOrSuiteNotFoundError)
  CheckSuiteNotFoundError = Class.new(CheckRunOrSuiteNotFoundError)

  retry_on CheckRunOrSuiteNotFoundError, wait: 1.minute, attempts: 2 do |job, error|
    GitHub.logger.error(
      "Failed due to Check run or suite not found error. Trying one more time.",
      "code.namespace" => "CreateCodeScanningAnnotationsJob",
      "code.function" => "CheckRunOrSuiteNotFoundError.catch",
      "gh.check_run.id" => job.check_run_id,
      :exception => error,
    )
    GitHub.dogstats.increment("code_scanning.annotations_job.find_check")
  end

  retry_on CodeScanning::PullRequestAlerts::DiffUnavailableError, wait: :polynomially_longer do |job, error|
    GitHub.logger.error(
      "Marking job as timed out due to PR diff being unavailable",
      "code.namespace" => "CreateCodeScanningAnnotationsJob",
      "code.function" => "perform",
      "gh.check_run.id" => job.check_run_id,
      :exception => error,
    )
    job.mark_check_run_timed_out
  end

  def perform(*args)
    log "Starting job."

    return fail_check_run_because_code_scanning_disabled unless repository&.code_scanning_enabled? && repository&.active?
    return ensure_check_suite_concluded if pr_already_closed_with_check_run_conclusion
    return if commit_oids_blank?
    return if base_ref_name.blank?

    if pull_request.nil?
      log "Pull request not found. Marking check run as neutral."
      return mark_check_run_neutral
    end

    # Check this here as update_check_run_from_diff will set check_run.completed_at
    first_completion = check_run.completed_at.blank?
    diff_summarizer = T.let(nil, T.nilable(CodeScanning::PullRequestAlertSummarizer))

    lock! do
      mark_check_run_in_progress

      diff_summarizer = new_diff_summarizer
      new_annotations_count = annotation_creator.create_annotations(check_run, diff_summarizer.new_alerts)
      manage_comments_if_possible(new_annotations_count, diff_summarizer)
      generate_suggested_fixes

      update_check_run_from_diff(diff_summarizer, first_completion)
    end

    emit_first_run_metrics if first_completion
    log_upload_to_annotation_metrics(diff_summarizer)
  end

  def check_run_id
    arguments.first[:check_run_id]
  end

  def mark_check_run_timed_out
    check_run.update(conclusion: "timed_out")
  end

  def mark_check_run_neutral
    check_run.update(conclusion: "neutral")
  end

  private

  # The reason why we are creating annotations
  def reason
    arguments.first[:reason] || :unknown
  end

  # Helper method for all logging from `perform` and the methods it calls
  def log(msg, other_log_params = {})
    GitHub.logger.info(msg,
      "code.namespace" => "CreateCodeScanningAnnotationsJob",
      "code.function" => "perform",
      "gh.repo.id" => repository&.id,
      "gh.check_run.id" => check_run&.id,
      **other_log_params
    )
  end

  def log_warn(msg, other_log_params = {})
    GitHub.logger.warn(msg,
      "code.namespace" => "CreateCodeScanningAnnotationsJob",
      "code.function" => "perform",
      "gh.repo.id" => repository&.id,
      "gh.check_run.id" => check_run&.id,
      **other_log_params
    )
  end

  def log_error(msg, other_log_params = {})
    GitHub.logger.error(msg,
      "code.namespace" => "CreateCodeScanningAnnotationsJob",
      "code.function" => "perform",
      "gh.repo.id" => repository&.id,
      "gh.check_run.id" => check_run&.id,
      **other_log_params
    )
  end

  def fail_check_run_because_code_scanning_disabled
    check_run.update(conclusion: "failure", title: "Code Scanning is not enabled on this repository")
  end

  def mark_check_run_in_progress
    check_run.update(status: "in_progress")
  end

  def pr_already_closed_with_check_run_conclusion
    check_run.conclusion.present? && pull_request.present? && !pull_request.open?
  end

  def ensure_check_suite_concluded
    # Make sure that the check_suite has the proper conclusion,
    # in case it missed it due to a race condition
    if check_run.check_suite.conclusion.nil?
      check_run.check_suite.set_rollup_values!
      # Emit a metric if this actually changed something
      GitHub.dogstats.increment("code_scanning.stale_check_suite") unless check_run.check_suite.conclusion.nil?
    end
  end

  def commit_oids_blank?
    base_commit_oid.blank? || (merge_commit_oid.blank? && head_commit_oid.blank?)
  end

  def code_scanning_bot
    return @code_scanning_bot if defined?(@code_scanning_bot)

    code_scanning_app = Apps::Privileged.integration(:code_scanning) or fail "code scanning integration not installed!"
    @code_scanning_bot = code_scanning_app.bot
  end

  def manage_comments_if_possible(new_annotations_count, diff_summarizer)
    return log("Cannot create review comments. The pull request is not present") unless pull_request.present?

    comment_creator = CodeScanning::CommentCreator.new(pull_request: pull_request, check_run: check_run, head_commit_oid: head_commit_oid, code_scanning_check_suite: code_scanning_check_suite)

    # Add onboarding comments if new categories are introduced
    if diff_summarizer.onboarding_experience_comment?
      comment_creator.create_onboarding_comment(reviewer: code_scanning_bot, body: diff_summarizer.onboarding_experience_comment)
    end

    if repository.code_scanning_pr_fixed_alerts_enabled?
      comment_creator.create_fixed_alerts_comment(reviewer: code_scanning_bot, fixed_count: diff_summarizer.fixed_count, check_run: check_run)
    end

    # we will try to create new review only if there is a new annotation
    if new_annotations_count > 0
      comment_creator.create_review_comments(diff_summarizer.new_alerts, code_scanning_bot)
    else
      log("No need to create new review comments since we didn't create any new annotations")
    end
    CodeScanning::CommentResolver.new(pull_request, head_commit_oid, merge_commit_oid).manage_fixed_comments(resolver: code_scanning_bot)

    comment_unresolver = CodeScanning::CommentUnresolver.new(pull_request: pull_request, head_commit_oid: head_commit_oid, merge_commit_oid: merge_commit_oid)
    comment_unresolver.manage_unfixed_comments(diff_summarizer.new_alerts, code_scanning_bot)

    comment_creator.log_summary
  end

  sig { returns(CodeScanning::PullRequestAlertSummarizer) }
  def new_diff_summarizer
    diff = pull_request.diffs
    diff.load_diff

    data = pr_alerts_from_diff!(diff)

    CodeScanning::PullRequestAlertSummarizer.new(
      pull_request_number: pull_request.number,
      repository: repository,
      tool_name: check_run.name,
      base_ref_name: base_ref_name,
      merge_ref_name: merge_ref_name,
      head_ref_name: head_ref_name,
      merge_commit_oid: merge_commit_oid,
      head_commit_oid: head_commit_oid,
      changes_too_large: @file_changes&.too_large?,

      fixed_alerts: data.fixed_alerts,
      fixed_count: data.fixed_count,
      new_alerts: data.new_alerts,
      new_count: data.new_count,
      new_categories: data.new_categories,
      missing_categories: data.missing_categories,
      latest_upload_time: data.latest_upload_time&.to_time,
      security_critical_count: data.security_critical_count,
      security_high_count: data.security_high_count,
      security_medium_count: data.security_medium_count,
      security_low_count: data.security_low_count,
      error_count: data.error_count,
      warning_count: data.warning_count,
      note_count: data.note_count,
    )
  end

  sig { params(diff: GitHub::Diff).returns(Turboscan::Proto::PullRequestAlertsResponse) }
  def pr_alerts_from_diff!(diff)
    tool_name = check_run.code_scanning_tool_name

    diff_status = CodeScanning::DiffStatus.new(diff)
    stats_tags = []
    stats_tags.concat diff_status.stats_tags

    @file_changes = begin
      GitHub.logger.with_named_tags(
        "code.namespace" => "CreateCodeScanningAnnotationsJob",
        "code.function" => "perform",
        "gh.repo.id" => repository&.id,
        "gh.check_run.id" => check_run&.id,
      ) do
        CodeScanning::PullRequestAlerts.file_changes(diff, include_deletions: repository.code_scanning_pr_fixed_alerts_enabled?)
      end
    rescue CodeScanning::PullRequestAlerts::DiffUnavailableError => e
      stats_tags.concat e.stats_tags

      GitHub.dogstats.increment("code_scanning.pull_request_alerts.result", tags: stats_tags)

      # Re-raise after having emitted stats about error as we don't need to call Turboscan
      raise
    end

    stats_tags.concat @file_changes.stats_tags

    response = GitHub::Turboscan.pull_request_alerts(
      repository_id: repository.id,
      tool: tool_name,
      head_commit_oid: head_commit_oid,
      merge_commit_oid: merge_commit_oid,
      base_ref_bytes: base_ref_name&.b,
      file_changes: @file_changes.array
    )

    stats_tags.concat CodeScanning::PullRequestAlerts.stats_tags_for_twirp_response(response)
    GitHub.dogstats.increment("code_scanning.pull_request_alerts.result", tags: stats_tags)

    if response&.error&.code == :not_found
      raise CodeScanning::PullRequestAlerts::NotFoundError, "Turboscan.PullRequestAlerts responded with 404"
    end

    if response.nil? || response.data.nil? || response.error.present?
      raise CodeScanning::PullRequestAlerts::RetriableTurboscanError.new("Turboscan.PullRequestAlerts endpoint failed for annotations job", repo_id: repository.id, twirp_error: response&.error)
    end

    T.must(response.data)
  end

  def generate_suggested_fixes
    return unless CodeScanning::Autofix.enabled_for_tool?(repository, check_run.code_scanning_tool_name)

    alert_numbers = pull_request.code_scanning_review_comments.where(fixed: false, tool_name: check_run.code_scanning_tool_name).pluck(:alert_number).uniq
    if alert_numbers.empty?
      log(
        "No alerts found to generate suggested fixes for",
        "gh.code_scanning.check_run.tool_name" => check_run.code_scanning_tool_name,
      )
      return
    end

    resp = CodeScanning::AutofixSuggestion.generate(
      repository: pull_request.repository,
      alert_numbers:,
      ref_names_bytes: code_scanning_check_suite.refs_bytes,
      source: :SUGGESTED_FIX_SOURCE_PR,
      pull_request_id: pull_request.id,
    )

    if resp&.data&.success
      log(
        "Successfully called Turboscan to generate suggested fixes",
        "gh.code_scanning.generate_suggested_fixes.alert_count" => alert_numbers.count,
        "gh.code_scanning.check_run.tool_name" => check_run.code_scanning_tool_name,
      )
    else
      log_error(
        "Failed to generate suggested fixes",
        "gh.code_scanning.generate_suggested_fixes.alert_count" => alert_numbers.count,
        "gh.code_scanning.generate_suggested_fixes.error" => resp&.error,
        "gh.code_scanning.check_run.tool_name" => check_run.code_scanning_tool_name,
      )
    end
  end

  def update_check_run_from_diff(diff_summarizer, first_completion)
    log "Updating check run for code scanning diff"
    check_run.update_for_code_scanning_diff!(diff_summarizer)
    log("Check run updated", "gh.check_run.previously_completed" => !first_completion)
  end

  def emit_first_run_metrics
    GitHub.dogstats.distribution("code_scanning.check_run.delay", check_run.duration)

    p50_success = check_run.duration < 10
    GitHub.dogstats.increment("github/code_scanning.slo", tags: ["name:latency/p50-check-run", "success:#{p50_success}"])
    p99_success = check_run.duration < 90
    GitHub.dogstats.increment("github/code_scanning.slo", tags: ["name:latency/p99-check-run", "success:#{p99_success}"])

    GitHub.dogstats.increment("code_scanning.check_run.completed")
  end

  def log_upload_to_annotation_metrics(diff_summarizer)
    return unless diff_summarizer.latest_upload_time

    time_in_secs = Time.now - diff_summarizer.latest_upload_time
    GitHub.dogstats.distribution("code_scanning.check_run.upload_to_annotation_secs",
                                 time_in_secs, tags: ["job_reason:#{reason}"])
    # Additional log suspicious cases
    if time_in_secs > 1.day
      log("Time since upload is quite big",
        "gh.pull_request.base_sha" => base_commit_oid,
        "gh.pull_request.head_sha" => head_commit_oid,
        "gh.pull_request.merge_sha" => merge_commit_oid,
        "gh.code_scanning.tool" => check_run.code_scanning_tool_name,
        "gh.code_scanning.job.reason" => reason.to_s,
        "gh.code_scanning.job.time" => time_in_secs,
      )
    end
  end

  def lock!
    restraint = GitHub::Restraint.new
    lock_key = "#{self.class.name}:#{check_run.id}"
    max_concurrent_jobs = 1
    lock_ttl = 5.minutes
    restraint.lock!(lock_key, max_concurrent_jobs, lock_ttl) do
      log "Obtained lock."
      yield
    end
  end

  def code_scanning_check_suite
    @code_scanning_check_suite ||= ActiveRecord::Base.connected_to(role: :writing) do
      CodeScanningCheckSuite.for_check_run(check_run)
    end
  end

  def base_commit_oid
    # Old check runs won't have a code_scanning_check_suite, so fall back to the
    # pull_request.
    code_scanning_check_suite&.base_sha.presence || pull_request&.base_sha
  end

  def merge_commit_oid
    # The merge commit may not be available if code scanning was run via push, an API upload, or based on an older default workflow
    code_scanning_check_suite&.pull_request_sha
  end

  def head_commit_oid
    # The head commit must always be available, one way or another.
    code_scanning_check_suite&.check_suite&.head_sha.presence || check_run.head_sha
  end

  def merge_ref_name
    return @merge_ref_name if defined?(@merge_ref_name)
    pull_request_ref = code_scanning_check_suite&.pull_request_ref
    return @merge_ref_name = pull_request_ref if File.fnmatch("refs/pull/*/merge", pull_request_ref.to_s)
    @merge_ref_name = nil
  end

  def head_ref_name
    return @head_ref_name if defined?(@head_ref_name)
    pull_request_ref = code_scanning_check_suite&.pull_request_ref
    return @head_ref_name = pull_request_ref if File.fnmatch("refs/pull/*/head", pull_request_ref.to_s)
    # Fall back to the branch name if the pull request ref is not a head commit or is unavailable
    return @head_ref_name = "refs/heads/#{code_scanning_check_suite.check_suite.head_branch}" unless code_scanning_check_suite&.check_suite&.head_branch.nil?
    @head_ref_name = nil
  end

  def base_ref_name
    @base_ref_name ||= code_scanning_check_suite&.base_ref
    if @base_ref_name.blank?
      GitHub.logger.info(
        "Base ref name is blank",
        "code.namespace" => "CreateCodeScanningAnnotationsJob",
        "code.function" => "base_ref_name",
        "gh.repo.id" => repository&.id,
        "gh.check_run.id" => check_run&.id,
        "gh.check_suite.id" => code_scanning_check_suite&.id,
        "gh.pull_request.base_ref.name" => @base_ref_name,
      )
    end

    @base_ref_name ||= repository.refs.find(pull_request&.base_ref)&.qualified_name
    if @base_ref_name.blank?
      GitHub.logger.info(
        "Base ref name is still blank after fallback",
        "code.namespace" => "CreateCodeScanningAnnotationsJob",
        "code.function" => "base_ref_name",
        "gh.repo.id" => repository&.id,
        "gh.check_run.id" => check_run&.id,
        "gh.check_suite.id" => code_scanning_check_suite&.id,
        "gh.pull_request.base_ref.name" => @base_ref_name,
      )
      error = StandardError.new("base ref name is blank")
      error.set_backtrace(caller)
      Failbot.report(error)
    end

    # Make sure that we are using full refs
    if !@base_ref_name.blank? && !@base_ref_name.start_with?("refs/heads")
      GitHub.logger.info(
        "Base ref name is not a full ref",
        "code.namespace" => "CreateCodeScanningAnnotationsJob",
        "code.function" => "base_ref_name",
        "gh.repo.id" => repository&.id,
        "gh.check_run.id" => check_run&.id,
        "gh.check_suite.id" => code_scanning_check_suite&.id,
        "gh.pull_request.base_ref.name" => @base_ref_name,
      )
      @base_ref_name = "refs/heads/#{@base_ref_name}"
    end

    @base_ref_name
  end

  def pull_request
    return @pull_request if defined? @pull_request
    @pull_request = repository.pull_requests_as_head.open_pulls.
      where(head_ref: Git::Ref.safe_ref_name(ref_names: check_run.check_suite.head_branch)).
      order(created_at: :desc).
      find { |pull_request| pull_request.repository&.active? }

    # Alternative way to compute the PR - This will hopefully be more robust.
    ref = code_scanning_check_suite&.pull_request_ref
    matcher = ref&.match(/\Arefs\/pull\/([0-9]+)\/(head|merge)\Z/)
    pull_request_new = nil
    if matcher
      pr_number = matcher[1]
      pull_request_new = PullRequest.with_number_and_repo(pr_number, repository)
    end

    # Log discrepancies
    if pull_request_new&.id != @pull_request&.id
      GitHub.logger.info(
        "Mismatch between two pull request implementations",
        "code.namespace" => "CreateCodeScanningAnnotationsJob",
        "code.function" => "pull_request",
        "gh.repo.id" => repository&.id,
        "gh.check_run.id" => check_run_id,
        "gh.pull_request.id.old" => @pull_request&.id,
        "gh.pull_request.id.new" => pull_request_new&.id,
      )
    end
    GitHub.dogstats.increment("code_scanning.annotations_job.find_pr", tags: ["pr_mismatch:#{pull_request_new&.id != @pull_request&.id}"])

    @pull_request ||= pull_request_new
    if @pull_request.blank?
      GitHub.logger.info(
        "Pull request is nil",
        "code.namespace" => "CreateCodeScanningAnnotationsJob",
        "code.function" => "pull_request",
        "gh.repo.id" => repository&.id,
        "gh.check_run.id" => check_run_id,
      )
    end

    @pull_request
  end

  def check_run
    @check_run ||= CheckRun.find_by(id: check_run_id).tap do |cr|
      raise(CheckRunNotFoundError) if cr.nil?
      raise(CheckSuiteNotFoundError) if cr.check_suite.nil?
    end
  end

  def repository
    @repository ||= check_run.repository
  end
end
