# typed: true
# frozen_string_literal: true

class Issue::Adapter::MilestoneEventAdapter < Issue::Adapter::IssueEventAdapter
  MILESTONED_EVENT = "MilestonedEvent"
  DEMILESTONED_EVENT = "DemilestonedEvent"

  attr_reader :milestone, :milestone_title

  def initialize(context, event_id:, event_name:)
    super(context, event_id: event_id, event_name: event_name)

    raise "Invalid event name" if event_name != MILESTONED_EVENT && event_name != DEMILESTONED_EVENT

    # milestone_title delegates to issue_event.issue_event_detail
    @milestone_title = @issue_event.milestone_title

    milestone = context.milestones_by_event_id[@issue_event.id]
    @milestone = Issue::Adapter::MilestoneAdapter.new(context, milestone: milestone) unless milestone.nil?
  end
end
