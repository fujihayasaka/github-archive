# typed: true
# frozen_string_literal: true

class Hook::Event::PullRequestReviewCommentEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS

  description "Pull request diff comment created, edited, or deleted."

  event_attr :action, :pull_request_review_comment_id, required: true
  event_attr :changes
  event_attr :actor_id

  def changes
    changes_attr = attributes.with_indifferent_access[:changes]
    return unless changes_attr

    {
      body: { from: changes_attr[:old_body] },
    }
  end

  def pull_request_review_comment
    @pull_request_review_comment ||= PullRequestReviewComment.find_by(id: pull_request_review_comment_id)
  end

  def pull_request
    pull_request_review_comment.pull_request
  end

  def target_repository
    pull_request_review_comment.try(:repository)
  end

  def actor
    return User.find_by(id: actor_id) if actor_id
    pull_request_review_comment.user
  end

  def deliverable?
    target_repository.present? && pull_request.present?
  end
end
