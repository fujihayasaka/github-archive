# typed: true
# frozen_string_literal: true

class Hook::Event::IssueCommentEvent < Hook::Event
  supports_targets *DEFAULT_TARGETS

  description "Issue comment created, edited, or deleted."

  event_attr :action, :issue_comment_id, required: true
  event_attr :old_body

  def issue_comment
    @issue_comment ||= IssueComment.find_by(id: issue_comment_id)
  end

  def issue
    issue_comment.issue
  end

  def deliverable?
    target_repository.present? && issue_comment.present? && issue.present?
  end

  def target_repository
    issue_comment.try(:repository)
  end

  def actor
    issue_comment.modifying_user
  end

  def changes
    return unless old_body

    GitHub.dogstats.increment("hooks.stale", tags: ["hook_event:issue_comments"]) if stale_changes?

    {
      body: { from: old_body },
    }
  end

  private

  # Private: Returns true if the changes that were passed in are equal to the
  # existing data we know about.
  #
  # Returns TrueClass or FalseClass.
  def stale_changes?
    return false unless body_changes?

    (body_changes? && old_body == issue_comment.body)
  end

  # Private: Returns true if the body has been changed.
  #
  # Returns TrueClass or FalseClass.
  def body_changes?
    old_body
  end
end
