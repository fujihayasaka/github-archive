# frozen_string_literal: true

# This job is retried in the case of GitHub errors. As such, it needs to be
# idempotent, even in the case where it errors out half-way through.
class UpdatePullRequestJob < ApplicationJob
  queue_as :update_pull_request
  default_retries_for_idempotent_jobs

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions: [
        *GitHubHelpers::RETRYABLE_ERRORS,
        Octokit::Unauthorized,
        UpdatePullRequest::GitHubTreeCreationBug,
      ],
    ),
    callback: proc do |e, _|
      raise if e.is_a?(ArgumentError) && e.message != "NULL pointer given"

      next unless e.is_a?(Octokit::Unauthorized)

      uncache_installation_client
    end,
  )

  rescue_from(UpdatePullRequest::BranchProtectionInvalidSignatureError) do |error|
    Dependabot::Logger.error(
      msg: "Unable to update Pull Request ##{pull_request.github_number}.",
      "code.namespace": self.class.name.to_s,
      "exception.type": error.class,
      "exception.message": error.message,
      **pull_request.telemetry_attributes,
    )

    increment_metric("update_pull_request.error")
  end

  # In the event we fail out with unauthorized, we should resync the repository as it is likely
  # we have lost access to it but failed to process the original uninstall event
  rescue_from(Octokit::Unauthorized) do
    SynchronizeRepoStateJob.perform_later(repo: pull_request.repo, event_source: "job.update_pull_request")

    increment_metric("update_pull_request.error")
  end

  # TODO: Make update_job_id a required argument in future
  #
  # We need to deploy with it as optional to permit any jobs in flight without
  # this parameter.
  def perform(pending_pull_request_update:, update_job_id: nil)
    @pending_pull_request_update = pending_pull_request_update
    @update_job = update_job_id ? UpdateJob.find_by(id: update_job_id) : nil
    return unless pull_request.account.active?

    setup_telemetry_tracking
    execute_pull_request_update
    cleanup_after_success
  rescue ActiveStorage::FileNotFoundError
    handle_file_not_found_error
  end

  private

  attr_reader :update_job, :pending_pull_request_update

  def setup_telemetry_tracking
    # pull_request telemetry but replacing the update_job_id with the one from this update
    telemetry_attributes = pull_request.telemetry_attributes.
                           merge(@update_job&.telemetry_attributes || {})

    Dependabot::Exceptions.push(telemetry_attributes)
  end

  def execute_pull_request_update
    # Update the pull request on GitHub
    UpdatePullRequest.new(
      pull_request: pull_request,
      updated_dependency_files: updated_dependency_files,
      new_base_commit_sha: new_base_commit_sha,
    ).run
  end

  def cleanup_after_success
    increment_metric("update_pull_request.success")
    pending_pull_request_update.encrypted_dependency_files_blob.purge
    pending_pull_request_update.destroy!
  end

  def handle_file_not_found_error
    # The files have expired on s3 in this case, which means we've not been able
    # to create an update to the PR in time. Re-enqueue a rebase in this case.
    # TODO: Pass the "manual" flag based on the original UpdateJob's trigger?
    EnqueueRebase.new(pull_request: pull_request, github_details: github_details).run
    if update_job
      update_job.increment_metric("update_pull_request.rebase_reenqueued")
    else
      MetricsClient.increment("update_pull_request_job.rebase_reenqueued")
    end
    increment_metric("update_pull_request.expired_files")
  end

  def increment_metric(metric)
    return unless update_job # TODO: Remove once update_job_id is required

    update_job.increment_metric(
      metric,
      tags: { grouped_update: pull_request.grouped_update }
    )
  end

  def pull_request
    pending_pull_request_update.pull_request
  end

  def updated_dependency_files
    pending_pull_request_update.updated_dependency_files
  end

  def new_base_commit_sha
    pending_pull_request_update.updated_base_commit_sha
  end

  def github_details
    @github_details ||=
      installation_github_client.pull_request(
        pull_request.repo.github_id,
        pull_request.github_number,
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
  end
end
