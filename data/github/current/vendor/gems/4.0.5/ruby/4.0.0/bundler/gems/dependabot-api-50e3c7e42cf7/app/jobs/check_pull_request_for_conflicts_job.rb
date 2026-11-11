# frozen_string_literal: true

require "github_helpers"
require "dependabot/file_updaters"

class CheckPullRequestForConflictsJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  MERGEABLE_RETRY_LIMIT = 5
  EVENT_SOURCE_AUTOMATIC = %w(job.create_scheduled_update hydro.repository_push).freeze
  AUTOMATIC_REBASES_DISABLED_NOTICE = <<~NOTICE
    > **Note**
    > Automatic rebases have been disabled on this pull request as it has been open for over 30 days.
  NOTICE

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

  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/AbcSize
  # rubocop:disable Metrics/PerceivedComplexity
  def perform(pull_request:, ignore_rebases_disabled_setting: false,
              mergeable_retries: 0, event_source: "unknown", manual: false)
    Dependabot::Exceptions.push(
      "gh.dependabot_api.pull_request.age_in_days": pull_request.age_in_days,
      "gh.dependabot_api.event.retries": mergeable_retries,
      "gh.dependabot_api.event.source": event_source,
      "gh.dependabot_api.event.manual": manual,
      **pull_request.telemetry_attributes,
    )

    @pull_request = pull_request
    @mergeable_retries = mergeable_retries
    @event_source = event_source
    @manual = manual

    # Check local Pull Request state
    return if automatic_rebasing_blocked?(ignore_rebases_disabled_setting)
    return unless pull_request.repo.account.active?

    # Fetch the Pull Request details from GitHub
    @github_details = fetch_github_details
    return add_automatic_rebases_disabled_notice_if_needed(github_details) if pr_is_too_old?

    # Handle synchronization issues
    return enqueue_job_to_resync_pr_state_if_necessary if github_details.merged || github_details.state == "closed"

    # Finally, check for non-dependabot commits
    return if pr_has_been_edited?

    Statesman::Machine.retry_conflicts { update_pull_request_if_dirty }
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "job.check_pull_request_for_conflicts",
    ).run
  rescue Octokit::UnprocessableEntity => e
    raise unless e.message.include?("this diff is taking too long")

    Dependabot::Logger.error(
      msg: "diff took too long",
      "code.namespace": "check_pull_request_for_conflicts_job",
      "exception.message": e.message,
      **pull_request.telemetry_attributes,
    )
    instrument_conflict_check(errored: true)
  end
  # rubocop:enable Metrics/MethodLength
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/PerceivedComplexity

  private

  attr_reader :github_details

  def pr_is_too_old?
    EVENT_SOURCE_AUTOMATIC.include?(event_source) && pull_request.too_old_for_automatic_rebase?
  end

  def add_automatic_rebases_disabled_notice_if_needed(github_details)
    return if github_details.body.include?("rebases have been disabled")

    updated_body = github_details.body.gsub(
      PullRequestFooter::AUTOMATICALLY_REBASE_PRS_TEXT,
      PullRequestFooter::MANUALLY_TRIGGER_REBASE_TEXT
    )

    # Two newlines here are necessary for presentation
    updated_body += "\n\n" + AUTOMATIC_REBASES_DISABLED_NOTICE

    UpdatePullRequestBody.new(
      pull_request: pull_request,
      updated_body: updated_body,
    ).run
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
    return unless dependency_details_changed?

    update_pull_request
  end

  def dependency_details_changed?
    package_manager = pull_request.update_config.package_manager

    regex_provider = EcosystemFileRegex.new(package_manager)
    file_regexes = regex_provider.updated_files_regex

    dependency_files_changed = files_changed_since_pr_created.select do |file|
      UpdateConfig.path_matches_updated_files_regex?(file_regexes,
                                                     file.filename)
    end

    dependency_files_changed.any? do |file|
      pull_request.updated_dependencies.any? do |dep|
        # Some dependencies use mixed-case in their names, so we call `downcase`
        # here to make sure they don't get ignored
        file.patch.to_s.downcase.include?(dep.name.downcase)
      end
    end
  end

  # This method is under active investigation to determine if there is a correlation
  # between PullRequest#age_in_days and us experiencing an error during comparison
  #
  # See: https://github.com/github/dependabot-updates/issues/2376
  def files_changed_since_pr_created
    return @files_changed_since_pr_created if defined?(@files_changed_since_pr_created)

    @files_changed_since_pr_created =
      installation_github_client.compare(
        pull_request.repo.github_id,
        github_details.base.sha,
        github_details.base.ref,
      ).files

    instrument_conflict_check(errored: false)
    @files_changed_since_pr_created
  end

  def retry_mergeable_later
    MetricsClient.increment("check_pull_request_conflicts.retry_mergeable")

    CheckPullRequestForConflictsJob.set(wait: 15.seconds).perform_later(
      pull_request: pull_request,
      mergeable_retries: mergeable_retries + 1,
      event_source: event_source,
      manual: manual
    )
  end

  def update_pull_request
    log_rebase

    EnqueueRebase.new(
      pull_request: pull_request,
      github_details: github_details,
      manual: manual,
    ).run
  end

  def automatic_rebases_disabled?
    !pull_request.update_config.automatically_rebase_prs?
  end

  def instrument_conflict_check(errored: false)
    MetricsClient.gauge("check_pull_request_for_conflicts.compare.pr_age_in_days",
                        pull_request.age_in_days,
                        tags: {
                          event_source: event_source,
                          manual: manual,
                          errored: errored,
                        })
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
