# typed: true
# frozen_string_literal: true

class Hook::Payload::PullRequestReviewCommentPayload < Hook::Payload
  delegate :action, :changes, :pull_request_review_comment, :pull_request, to: :hook_event

  def to_payload_hash
    pull_request = T.let(hook_event.pull_request, PullRequest)
    comment = T.let(hook_event.pull_request_review_comment, PullRequestReviewComment)

    if pull_request.repository&.feature_enabled?(:pull_requests_rest_serialize_new_positioning)
      if thread = comment.pull_request_review_thread
        thread.preloaded_positioning = PullRequests::CommentPosition::Legacy::Conversion.for_thread(pull_request:, thread:)
      end
    end

    {}.tap do |payload|
      payload[:action]       = action
      payload[:changes]      = changes if changes
      payload[:comment]      = api_serialize(:pull_request_review_comment_hash, comment)
      payload[:pull_request] = api_serialize(:pull_request_hash, pull_request, hook: true, show_merge_settings: true)
    end
  end
end
