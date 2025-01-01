# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::BaseRefDeletedEventAdapter < Issue::Adapter::IssueEventAdapter
  BASE_REF_DELETED_EVENT = "BaseRefDeletedEvent"

  attr_reader :pull_request, :issue_event, :actor

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: BASE_REF_DELETED_EVENT)
    @pull_request = context.pull_request
    @actor = @context.users_by_id[@issue_event.actor_id]
  end
end
