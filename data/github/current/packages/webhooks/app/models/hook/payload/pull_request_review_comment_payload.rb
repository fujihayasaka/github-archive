# typed: true
# frozen_string_literal: true

class Hook::Payload::PullRequestReviewCommentPayload < Hook::Payload
  delegate :action, :changes, :pull_request_review_comment, :pull_request, to: :hook_event

  def to_payload_hash
    {}.tap do |payload|
      payload[:action]       = action
      payload[:changes]      = changes if changes
      payload[:comment]      = api_serialize(:pull_request_review_comment_hash, pull_request_review_comment)
      payload[:pull_request] = api_serialize(:pull_request_hash, pull_request, hook: true, show_merge_settings: true)
    end
  end
end
