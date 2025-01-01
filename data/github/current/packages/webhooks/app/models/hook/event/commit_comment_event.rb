# typed: true
# frozen_string_literal: true

class Hook::Event::CommitCommentEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  description "Commit or diff commented on."

  event_attr :action, :commit_comment_id, required: true

  def commit_comment
    @commit_comment ||= CommitComment.find_by(id: commit_comment_id)
  end

  def target_repository
    commit_comment.try(:repository)
  end

  def actor
    commit_comment.user
  end

  def deliverable?
    target_repository.present?
  end
end
