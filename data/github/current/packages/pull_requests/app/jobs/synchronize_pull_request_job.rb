# typed: true
# frozen_string_literal: true

class SynchronizePullRequestJob < ApplicationJob
  queue_as :synchronize_pull_request

  # Allow write connections to these clusters.
  use_primaries ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes

  use_replicas ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Permissions,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::RepositoriesPushes,
    allow_replication_lag: [
      ApplicationRecord::Iam,
      ApplicationRecord::Notify
    ]

  retry_on_dirty_exit

  retry_on PullRequest::DetermineCodeownersError, attempts: 1 do |job, error|
    GitHub.dogstats.increment("pull_request.synchronize_pull_request_job.determine_codeowners_error")

    if job.repo&.feature_enabled?(:pr_sync_log_determine_codeowners_errors)
      GitHub.logger.info("PullRequest::DetermineCodeownersError occurred during SynchronizePullRequestJob",
        "code.function" => "SynchronizePullRequestJob",
        "gh.pull_request.id" => job.pull_request&.id,
        "gh.pull_request.head_sha" => job.pull_request&.head_sha,
        "gh.pull_request.base_sha" => job.pull_request&.base_sha,
        "gh.pull_request.created_at" => job.pull_request&.created_at,
        "gh.pull_request.codeowners.error" => error.message,
      )
    else
      raise error
    end
  end

  retry_on SpokesAPI::ResourceExhausted, wait: 15, attempts: 2
  class SpokesResourceExhaustedLongRetry < StandardError; end
  retry_on SpokesResourceExhaustedLongRetry, wait: 5.minutes, jitter: 0.5, attempts: 10

  discard_on ActiveRecord::RecordNotFound do |_, error|
    Failbot.report(error)
  end

  attr_accessor :pull_request, :repo

  def perform(pull_request_id:, user:, installation:, repo:, forced:, ref:, before:, after:, should_mark_merged: nil,
    precomputed_merge_oids: nil, promote_reviews: false, push_options: nil, non_compliant_merge: false, pushed_at: nil, **kwargs)

    Failbot.push(
      "gh.repo.id": repo&.id,
      "gh.user.id": user&.id
    )

    unless repo.active?
      GitHub.logger.info("synchronize_pull_request_job_no_repository")
      GitHub.dogstats.increment("pull_request", tags: ["action:synchronize_skipped_no_repository"])
      return
    end

    self.repo = repo

    if user && installation
      user.installation = installation
    end
    self.pull_request = PullRequest.find(pull_request_id)
    unless pull_request.repository
      GitHub.dogstats.increment("pull_request", tags: ["action:synchronize_skipped_no_repository"])
      return
    end

    age_in_hours = (Time.current - pull_request.updated_at) / 1.hour
    GitHub.dogstats.distribution("pull_request.synchronize_pull_request_job.dist.pull_request_age", age_in_hours)

    # Don't use || to coalesce this -- false is a valid value.
    should_mark_merged = BatchIsPullRequestMerged::NotPrecomputed if should_mark_merged.nil?

    begin
      pull_request.synchronize!(user:, repo:, forced:, ref:, before:, after:, should_mark_merged:, precomputed_merge_oids:,
        promote_reviews:, push_options:, non_compliant_merge:, pushed_at:)
    rescue SpokesAPI::ResourceExhausted
      raise unless pull_request.repository&.feature_enabled?(:pr_sync_longer_spokes_retry) || pull_request.head_repository&.feature_enabled?(:pr_sync_longer_spokes_retry)

      # for known troublesome repositories we want to retry with a much longer wait to give spokes a better chance to recover
      raise SpokesResourceExhaustedLongRetry
    end
  end

  # Since the user is supplied to perform as an ActiveRecord model
  # we need to ensure we use the replica during deserialization too
  def deserialize_arguments_if_needed
    use_mysql1_replica do
      super
    end
  end
end
