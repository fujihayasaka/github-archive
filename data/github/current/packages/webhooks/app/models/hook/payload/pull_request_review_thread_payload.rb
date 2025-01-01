# typed: true
# frozen_string_literal: true

class Hook::Payload::PullRequestReviewThreadPayload < Hook::Payload

  def to_payload_hash
    {
      action: hook_event.action,
      pull_request: api_serialize(:pull_request_hash, hook_event.pull_request),
      thread: api_serialize(:pull_request_review_thread_hash, hook_event.thread.async_to_deprecated_thread.sync),
    }
  end
end
