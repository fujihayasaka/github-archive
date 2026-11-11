# frozen_string_literal: true

# Wrapper for performing an action in response to a GitHub pull request. Note
# that we do the initial comment parsing in the request cycle - this is only
# used for responding.
class HandlePullRequestCommentJob < ApplicationJob
  include GitHub::Telemetry::Traces::Traceable

  queue_as :default
  default_retries_for_idempotent_jobs

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions: [
        *GitHubHelpers::RETRYABLE_ERRORS,
        GitHub::Twirp::DependabotPullRequests::TransientServiceError,
        GitHub::Twirp::DependabotPullRequests::TransientTwirpError,
      ]
    ),
  )

  def perform(action:, requester_id: nil, args: [], keyword_args: {})
    telemetry_attributes = {
      "gh.dependabot_api.pull_request_event.action_name" => action,
      "gh.actor.id" => requester_id,
      "gh.comment.id" => keyword_args[:comment_id],
    }
    tracer.in_span("#{self.class.name}#perform", attributes: telemetry_attributes) do
      action.constantize.new(*args, **keyword_args).run
    end
  rescue RepoPermissionChecker::InaccessibleRepo
    # No-op if repo is inaccessible
    nil
  end
end
