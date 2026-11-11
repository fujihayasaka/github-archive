# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::HeadRefDeletedOrRestoredEventAdapter < PullRequest::Adapter::IssueEventAdapter
  HEAD_REF_DELETED_EVENT = "HeadRefDeletedEvent"
  HEAD_REF_RESTORED_EVENT = "HeadRefRestoredEvent"

  attr_reader :action, :pull_request

  def initialize(context, event_id:)
    super(context, event_id: event_id)
    @pull_request = context.pull_request
  end
end
