# frozen_string_literal: true

# Wrapper for updating a pull request's CI status. Doing this in a job allows
# us to retry any exceptions from GitHub (server errors or connection failures).
class UpdatePullRequestCiStatusJob < ApplicationJob
  include LockingJob

  # This debounce period should be used with high job volume scheduling.
  # This makes enqueue locking more powerful and reduces more redundant job
  # executions in cases where multiple updates are triggered
  # in a short period of time.
  DEBOUNCE_PERIOD = 40.seconds

  queue_as :default
  default_retries_for_idempotent_jobs

  # This job uses enqueue locking to avoid enqueuing multiple jobs for the same PR
  # and refs in a short period of time.
  locked_by timeout: 1.minute, key: lambda { |job|
    pr_id = job.arguments.first[:pull_request_id] || job.arguments.first[:pull_request]&.id
    refs_to_check = Array(job.arguments.first[:refs_to_check]).compact.uniq.sort
    refs = refs_to_check.join(",")
    "pr:#{pr_id}/refs:#{refs}"
  }

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions:
        [
          *GitHubHelpers::RETRYABLE_ERRORS,
          GitHub::Twirp::DependabotPullRequests::TransientServiceError,
          GitHub::Twirp::DependabotPullRequests::TransientTwirpError,
        ],
    ),
  )

  def deserialize(job_data)
    ActiveRecord::Base.connected_to(role: :reading) do
      super
    end
  end

  # Generally `pull_request` arg is preferred, but we do have use cases where `pull_request_id` makes more sense:
  # https://github.com/github/dependabot-api/pull/3317#pullrequestreview-1194561854
  def perform(refs_to_check:, pull_request: nil, pull_request_id: nil)
    @pull_request = if pull_request_id.present?
                      ActiveRecord::Base.connected_to(role: :reading) do
                        PullRequest.find(pull_request_id)
                      end
                    elsif pull_request.present?
                      pull_request
                    else
                      raise ArgumentError, "Must provide either pull_request or pull_request_id"
                    end

    UpdatePullRequestCiStatus.new(
      pull_request: @pull_request,
      refs_to_check: refs_to_check,
    ).run
  end
end
