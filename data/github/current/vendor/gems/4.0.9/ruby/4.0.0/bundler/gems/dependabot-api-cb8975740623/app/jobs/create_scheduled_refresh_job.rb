# frozen_string_literal: true

# This job enqueues a rebase for the given pull request regardless of whether
# it is in conflict with the target branch in GitHub.
#
# This is primarily used to refresh Grouped Update pull requests which have
# been left open since the last time the schedule ran.
#
# Unlike CheckPullRequestForConflictsJob, this job will still trigger a rebase
# even if:
# 1. The Pull Request is not in conflict with base
# 2. The Pull Request has been editted by someone other than Dependabot
#
# In the case of (1) `actions/update_pull_request` will ultimately prevent any
# update to the pull request going ahead but this gives us an opportunity to
# determine that the dependencies and/or content of the PR has changed and
# we should supersede it.
#
# For Grouped Updates, this is necessary to ensure that an edit does not
# block us from attempting to refresh a Dependency Group indefinitely.
class CreateScheduledRefreshJob < ApplicationJob
  queue_as :scheduled_updates
  default_retries_for_idempotent_jobs

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

  def perform(pull_request:, event_source:, manual: false)
    @pull_request = pull_request
    @event_source = event_source
    @manual = manual

    log_job_start

    return log_account_inactive unless pull_request.repo.account.active?

    # Fetch the Pull Request details from GitHub
    @github_details = fetch_github_details

    return handle_resolved_pr if pr_has_been_resolved_on_github?
    return handle_stale_group if pr_has_stale_group?

    refresh_pull_request
  rescue *SynchronizeRepoState::HANDLED_ERRORS => e
    log_sync_error(e)
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "job.create_scheduled_refresh_job",
    ).run
  end

  private

  attr_reader :pull_request, :event_source, :manual, :github_details

  def fetch_github_details
    installation_github_client.pull_request(
      pull_request.repo.github_id,
      pull_request.github_number,
    )
  end

  def pr_has_been_resolved_on_github?
    github_details.merged || github_details.state == "closed"
  end

  def enqueue_resync_pr_state_if_necessary
    current_state = pull_request.current_state.to_sym
    return if github_details.merged && current_state == :merged
    return if github_details.state == "closed" && current_state == :closed

    log_enqueuing_resync_pr_state
    ResyncPrStateJob.perform_later(pull_request: pull_request)
  end

  def pr_has_stale_group?
    return false unless pull_request.grouped_update?
    return false if pull_request.multi_ecosystem_config_id?

    !pull_request.dependency_group&.active?
  end

  def handle_resolved_pr
    log_pr_resolved_on_github
    enqueue_resync_pr_state_if_necessary
  end

  def handle_stale_group
    log_stale_group_detected
    enqueue_close_pull_request
  end

  def enqueue_close_pull_request
    log_enqueuing_close_pull_request
    ClosePullRequestJob.perform_later(pull_request: pull_request, reason: "dependency_group_deleted")
  end

  def refresh_pull_request
    Dependabot::Logger.info(
      msg: "enqueuing pull request rebase",
      "code.namespace": "CreateScheduledRefreshJob",
      "gh.dependabot_api.event.source": event_source,
      manual: manual,
      "gh.pull_request.current_state": pull_request.current_state,
      grouped_update: pull_request.grouped_update?,
      **pull_request.telemetry_attributes,
    )

    EnqueueRebase.new(
      pull_request: pull_request,
      github_details: github_details,
      manual: manual,
    ).run
  end

  def log_job_start
    Dependabot::Logger.info(
      msg: "starting scheduled refresh job",
      "code.namespace": "CreateScheduledRefreshJob",
      "gh.dependabot_api.event.source": event_source,
      manual: manual,
      **pull_request.telemetry_attributes,
    )
  end

  def log_account_inactive
    Dependabot::Logger.info(
      msg: "skipping scheduled refresh for inactive account",
      "code.namespace": "CreateScheduledRefreshJob",
      "gh.dependabot_api.event.source": event_source,
      **pull_request.telemetry_attributes,
    )
  end

  def log_pr_resolved_on_github
    Dependabot::Logger.info(
      msg: "pull request resolved on github",
      "code.namespace": "CreateScheduledRefreshJob",
      "gh.dependabot_api.event.source": event_source,
      "gh.pull_request.merged": github_details.merged,
      "gh.pull_request.state": github_details.state,
      **pull_request.telemetry_attributes,
    )
  end

  def log_stale_group_detected
    Dependabot::Logger.info(
      msg: "stale dependency group detected",
      "code.namespace": "CreateScheduledRefreshJob",
      "gh.dependabot_api.event.source": event_source,
      grouped_update: pull_request.grouped_update?,
      multi_ecosystem_config: pull_request.multi_ecosystem_config_id?,
      dependency_group_active: pull_request.dependency_group&.active?,
      **pull_request.telemetry_attributes,
    )
  end

  def log_enqueuing_resync_pr_state
    Dependabot::Logger.info(
      msg: "enqueuing resync pr state job",
      "code.namespace": "CreateScheduledRefreshJob",
      "gh.dependabot_api.event.source": event_source,
      "gh.pull_request.current_state": pull_request.current_state,
      "gh.pull_request.github_merged": github_details.merged,
      "gh.pull_request.github_state": github_details.state,
      **pull_request.telemetry_attributes,
    )
  end

  def log_enqueuing_close_pull_request
    Dependabot::Logger.info(
      msg: "enqueuing close pull request job for stale group",
      "code.namespace": "CreateScheduledRefreshJob",
      "gh.dependabot_api.event.source": event_source,
      reason: "dependency_group_deleted",
      **pull_request.telemetry_attributes,
    )
  end

  def log_sync_error(exception)
    Dependabot::Logger.error(
      msg: "synchronization error during scheduled refresh",
      "code.namespace": "CreateScheduledRefreshJob",
      "gh.dependabot_api.event.source": event_source,
      "exception.message": exception.message,
      "exception.type": exception.class.name,
      **pull_request.telemetry_attributes,
    )
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.new(
        account: pull_request.repo.account,
      )
  end

  def uncache_installation_client
    GitHubHelpers.delete_cached_access_token_for(
      account: pull_request.repo.account,
    )
    @installation_github_client = nil
  end
end
