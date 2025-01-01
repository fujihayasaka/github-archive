# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::HeadRefForcePushedEventAdapter < PullRequest::Adapter::IssueEventAdapter
  HEAD_REF_FORCE_PUSHED_EVENT = "HeadRefForcePushedEvent"

  attr_reader :pull_request, :issue_event, :actor, :created_at

  def initialize(context, event_id:)
    super(context, event_id: event_id)
    @pull_request = context.pull_request
    @actor = context.users_by_id[@issue_event.actor_id]
    @created_at = @issue_event.created_at
  end
end
