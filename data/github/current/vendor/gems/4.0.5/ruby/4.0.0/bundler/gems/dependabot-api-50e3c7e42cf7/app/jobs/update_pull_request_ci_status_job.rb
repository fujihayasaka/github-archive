# frozen_string_literal: true

# Wrapper for updating a pull request's CI status. Doing this in a job allows
# us to retry any exceptions from GitHub (server errors or connection failures).
class UpdatePullRequestCiStatusJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

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
