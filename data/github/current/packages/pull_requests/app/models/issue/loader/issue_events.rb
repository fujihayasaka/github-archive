# typed: true
# frozen_string_literal: true

class Issue::Loader::IssueEvents < Issue::Loader::Base
  def initialize(context, issue_event_ids: [])
    @context = context
    @issue_event_ids = issue_event_ids
  end

  def self.preload_issue_events_for(context)
    new(context).preload_issue_events
  end

  def preload_issue_events
    track_execution_time do
      async_preload_attribute(
        @context.events,
        :can_view_actor,
        :async_can_view_actor?,
        [@context.viewer]
      ).sync
    end
  end
end
