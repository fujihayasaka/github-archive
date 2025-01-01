# typed: true
# frozen_string_literal: true

class Issue::Loader::Milestones < Issue::Loader::Base
  def initialize(context, milestone_events: [])
    @context = context
    @milestone_events = milestone_events
  end

  def self.load_for(context, milestone_events: [])
    super new(context, milestone_events: milestone_events)
  end

  def load
    Promise.all(
      @milestone_events.map do |e|
        e.async_milestone.then do |milestone|
          [e.id, milestone]
        end
      end
    ).then do |event_ids_and_milestones|
      event_ids_and_milestones.to_h.tap do |milestones_by_event_id|
        @context.preload_attr(:milestones_by_event_id, milestones_by_event_id)
      end
    end.sync
  end
end
