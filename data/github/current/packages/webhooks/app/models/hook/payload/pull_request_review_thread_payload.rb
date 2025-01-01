# typed: true
# frozen_string_literal: true

class Hook::Payload::PullRequestReviewThreadPayload < Hook::Payload
  def to_payload_hash
    thread = T.let(hook_event.thread, ::PullRequestReviewThread)
    pull_request = T.let(hook_event.pull_request, PullRequest)

    if pull_request.repository&.feature_enabled?(:pull_requests_rest_serialize_new_positioning)
      thread.preloaded_positioning = PullRequests::CommentPosition::Legacy::Conversion.for_thread(pull_request:, thread:)
    end

    {
      action: hook_event.action,
      pull_request: api_serialize(:pull_request_hash, pull_request),
      thread: api_serialize(:pull_request_review_thread_hash, thread.async_to_deprecated_thread.sync),
    }.tap do |payload_hash|
      payload_hash[:updated_at] = thread.updated_at.iso8601 unless thread.updated_at.nil?
    end
  end
end
