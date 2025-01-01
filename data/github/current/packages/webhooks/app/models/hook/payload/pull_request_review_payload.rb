# typed: true
# frozen_string_literal: true

class Hook::Payload::PullRequestReviewPayload < Hook::Payload
  delegate :action, :changes, :pull_request_review, :pull_request, to: :hook_event

  def to_payload_hash
    {}.tap do |payload|
      payload[:action]       = action
      payload[:review]       = api_serialize(:pull_request_review_hash, pull_request_review)
      payload[:pull_request] = api_serialize(:pull_request_hash, pull_request, hook: true, show_merge_settings: true)
      payload[:changes]      = changes if changes
    end
  end
end
