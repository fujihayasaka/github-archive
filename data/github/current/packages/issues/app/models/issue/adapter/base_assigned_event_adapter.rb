# typed: true
# frozen_string_literal: true

# This is a union type of both the assigned and unassigned events.
# We use it for type checks in the views.
# It mirrors the platform events.
class Issue::Adapter::BaseAssignedEventAdapter < Issue::Adapter::IssueEventAdapter
  ASSIGNED_EVENT = "AssignedEvent"
  UNASSIGNED_EVENT = "UnassignedEvent"

  attr_reader :assignee

  def initialize(context, event_id:, event_name:)
    super(context, event_id: event_id, event_name: event_name)

    @assignee = context.users_by_id[@issue_event.actor_id]
    @actor = @issue_event.issue_event_detail.subject
  end
end
