# typed: true
# frozen_string_literal: true

class Issue::Adapter::CommentDeletedEventAdapter < Issue::Adapter::IssueEventAdapter
  COMMENT_DELETED_EVENT = "CommentDeletedEvent"

  attr_reader :deleted_comment_author

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: COMMENT_DELETED_EVENT)
    actor = @context.users_by_id[@issue_event.subject_id]
    @deleted_comment_author = actor unless actor&.hide_from_user?(context.viewer)
  end
end
