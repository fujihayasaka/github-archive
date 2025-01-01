# typed: true
# frozen_string_literal: true

class Hook::Event::CommitCommentEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS
  description "Commit or diff commented on."

  event_attr :action, :commit_comment_id, required: true
  event_attr :old_body, :actor_id

  def commit_comment
    @commit_comment ||= CommitComment.find_by(id: commit_comment_id)
  end

  def target_repository
    commit_comment.try(:repository)
  end

  def actor
    return @actor if defined?(@actor)

    @actor = if actor_id
      User.find_by(id: actor_id) || User.ghost
    else
      commit_comment.try(:user)
    end
  end

  def deliverable?
    target_repository.present?
  end

  def changes
    return unless old_body

    {
      body: { from: old_body },
    }
  end
end
