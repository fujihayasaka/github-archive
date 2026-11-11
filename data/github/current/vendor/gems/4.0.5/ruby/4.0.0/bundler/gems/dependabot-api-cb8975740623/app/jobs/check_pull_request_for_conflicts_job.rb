# frozen_string_literal: true

require "github_helpers"
require "dependabot/file_updaters"

class CheckPullRequestForConflictsJob < ApplicationJob
  include LockingJob

  queue_as :default
  default_retries_for_idempotent_jobs

  MERGEABLE_RETRY_LIMIT = 5
  EVENT_SOURCE_AUTOMATIC = %w(job.create_scheduled_update hydro.repository_push).freeze
  AUTOMATIC_REBASES_DISABLED_NOTICE = <<~NOTICE
    > **Note**
    > Automatic rebases have been disabled on this pull request as it has been open for over 30 days.
  NOTICE

  # This debounce period should be used with high job volume scheduling.
  # This makes enqueue locking more powerful and reduces redundant job
  # executions in cases where multiple conflict checks are triggered
  # for the same pull request in a short period of time.
  DEBOUNCE_PERIOD = 60.seconds

  # This job uses enqueue locking to avoid enqueuing multiple jobs for the same PR
  # in a short period of time. The lock key is derived from the pull request ID,
  # manual flag and ignore_rebases_disabled_setting flag as they are direct inputs to the job.
  locked_by timeout: 2.minutes, key: lambda { |job|
    pr = job.arguments.first[:pull_request]
    manual = job.arguments.first[:manual]
    ignore_rebases_disabled_setting = job.arguments.first[:ignore_rebases_disabled_setting]
    next nil unless debounce_enabled_for?(pr)

    "pr:#{pr.id}-manual:#{manual}-irds:#{ignore_rebases_disabled_setting}"
  }

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions:
        [*GitHubHelpers::RETRYABLE_ERRORS, Octokit::Unauthorized],
    ),
    callback: proc do |exception, _|
      next unless exception.is_a?(Octokit::Unauthorized)

      uncache_installation_client
    end,
  )

  attr_reader :pull_request, :mergeable_retries, :event_source, :manual

  # Enqueue with debounce delay when the feature flag is enabled.
  # This should be used by all external callers. Internal self-retries
  # (e.g. retry_mergeable_later) should call perform_later directly.
  def self.enqueue_with_debounce(**kwargs)
    wait = kwargs.delete(:wait) || 0
    wait += DEBOUNCE_PERIOD if debounce_enabled_for?(kwargs[:pull_request])

    if wait.positive?
      set(wait: wait).perform_later(**kwargs)
    else
      perform_later(**kwargs)
    end
  end

  def self.debounce_enabled_for?(pull_request)
    return false unless pull_request

    T.unsafe(Dependabot::Application).monolith_feature_enabled?(
      feature: :dependabot_debounce_conflict_checks,
      use_cache: true
    )
  end

  def perform(pull_request:, ignore_rebases_disabled_setting: false,
              mergeable_retries: 0, event_source: "unknown", manual: false)
    @pull_request = pull_request
    @mergeable_retries = mergeable_retries
    @event_source = event_source
    @manual = manual

    push_exception_context
    log_job_telemetry

    check_for_conflicts(ignore_rebases_disabled_setting: ignore_rebases_disabled_setting)
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "job.check_pull_request_for_conflicts",
    ).run
  end

  private

  attr_reader :github_details

  def check_for_conflicts(ignore_rebases_disabled_setting:)
    return if automatic_rebasing_blocked?(ignore_rebases_disabled_setting)
    return unless pull_request.repo.account.active?

    @github_details = fetch_github_details
    return add_automatic_rebases_disabled_notice_if_needed(github_details) if pr_is_too_old?
    return enqueue_job_to_resync_pr_state_if_necessary if github_details.merged || github_details.state == "closed"
    return if pr_has_been_edited?

    Statesman::Machine.retry_conflicts { update_pull_request_if_dirty }
  end

  def push_exception_context
    Dependabot::Exceptions.push(
      "gh.dependabot_api.pull_request.age_in_days": pull_request.age_in_days,
      "gh.dependabot_api.event.retries": mergeable_retries,
      "gh.dependabot_api.event.source": event_source,
      "gh.dependabot_api.event.manual": manual,
      **pull_request.telemetry_attributes,
    )
  end

  def pr_is_too_old?
    EVENT_SOURCE_AUTOMATIC.include?(event_source) && pull_request.too_old_for_automatic_rebase?
  end

  def add_automatic_rebases_disabled_notice_if_needed(github_details)
    body = github_details.body.to_s
    return if body.include?("rebases have been disabled")

    updated_body = body.gsub(
      PullRequestFooter::AUTOMATICALLY_REBASE_PRS_TEXT,
      PullRequestFooter::MANUALLY_TRIGGER_REBASE_TEXT,
    ) + "\n\n" + AUTOMATIC_REBASES_DISABLED_NOTICE # Two newlines here are necessary for presentation

    UpdatePullRequestBody.new(pull_request: pull_request, updated_body: updated_body).run
  end

  def automatic_rebasing_blocked?(ignore_rebases_disabled_setting)
    return true if mergeable_retries > MERGEABLE_RETRY_LIMIT
    return true if automatic_rebases_disabled? && !ignore_rebases_disabled_setting && !pull_request.merge_requested?
    return true if pull_request.in_state?(:updating)

    false
  end

  def enqueue_job_to_resync_pr_state_if_necessary
    current_state = pull_request.current_state.to_sym
    return if github_details.merged && current_state == :merged
    return if github_details.state == "closed" && current_state == :closed

    ResyncPrStateJob.perform_later(pull_request: pull_request)
  end

  def pr_has_been_edited?
    PullRequestCommits.new(pull_request: pull_request).
      pr_has_been_edited?(head_sha: github_details.head.sha)
  end

  def fetch_github_details
    installation_github_client.pull_request(
      pull_request.repo.github_id,
      pull_request.github_number,
    )
  end

  def update_pull_request_if_dirty
    # Short circuit checking if dependency files have changed (big request)
    return update_pull_request if github_details.mergeable == false
    # GitHub has started a background job to compute the mergeability so we
    # should give the job time to complete and retry
    return retry_mergeable_later if github_details.mergeable.nil?

    # The state "behind" is only used when a branch cannot be merged because
    # it is behind. We should automatically rebase in these cases.
    return update_pull_request if github_details.mergeable_state == "behind"

    # Check if dependency files have changed. Note we *can't* just rely on
    # mergeability, as if the dependency has been updated in a separate PR
    # then this PR may still be mergeable, but just have no effect (in which
    # case the update run will close it).
    return unless dependency_files_changed?

    update_pull_request
  end

  # This method is under active investigation to determine if there is a correlation
  # between PullRequest#age_in_days and us experiencing an error during comparison
  #
  # See: https://github.com/github/dependabot-updates/issues/2376
  def dependency_files_changed?
    return @dependency_files_changed if instance_variable_defined?(:@dependency_files_changed)

    @dependency_files_changed = PullRequestDependencyChangeDetector.new(
      pull_request: pull_request,
      github_details: github_details,
      github_client: installation_github_client,
    ).changed?
    @dependency_files_changed
  end

  def retry_mergeable_later
    MetricsClient.increment("check_pull_request_conflicts.retry_mergeable",
                            tags: { event_source: event_source, manual: manual, mergeable_retries: mergeable_retries })

    CheckPullRequestForConflictsJob.set(wait: 15.seconds).perform_later(pull_request: pull_request,
                                                                        mergeable_retries: mergeable_retries + 1,
                                                                        event_source: event_source,
                                                                        manual: manual)
  end

  def update_pull_request
    log_rebase
    EnqueueRebase.new(pull_request: pull_request, github_details: github_details, manual: manual).run
  end

  def automatic_rebases_disabled?
    !pull_request.update_config.automatically_rebase_prs?
  end

  def log_rebase
    Dependabot::Logger.info(
      msg: "enqueuing pull request rebase",
      "code.namespace": "CheckPullRequestForConflictsJob",
      "gh.dependabot_api.event.source": event_source,
      **pull_request.telemetry_attributes,
    )
  end

  def installation_github_client
    @installation_github_client ||= GitHubHelpers::ClientWithRetries.new(account: pull_request.repo.account)
  end

  def uncache_installation_client
    GitHubHelpers.delete_cached_access_token_for(account: pull_request.repo.account)
    @installation_github_client = nil
  end

  def log_job_telemetry
    return unless pull_request.repo.monolith_feature_enabled?(:dependabot_log_check_pull_request_for_conflicts)

    Dependabot::Logger.info(
      msg: "checking for pr conflicts",
      "code.namespace": "CheckPullRequestForConflictsJob",
      "gh.dependabot_api.event.source": event_source,
      attempt: mergeable_retries,
      **pull_request.telemetry_attributes,
    )
  end
end
