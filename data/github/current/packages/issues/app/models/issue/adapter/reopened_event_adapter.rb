# typed: true
# frozen_string_literal: true

class Issue::Adapter::ReopenedEventAdapter < Issue::Adapter::IssueEventAdapter
  REOPENEND_EVENT = "ReopenedEvent"

  attr_reader :closable
  attr_reader :state_reason

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: REOPENEND_EVENT)
    event = context.events_by_id[event_id]

    issue = context.issue
    @state_reason = event.state_reason&.upcase

    @closable = Issue::Adapter::ClosableAdapter.new(context)
  end

end
