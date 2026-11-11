# typed: true
# frozen_string_literal: true

module DependabotAlerts::TimelineItems
  class AssignmentComponent < ApplicationComponent
    VALID_ACTIONS = %i[assigned unassigned].freeze

    attr_reader :event, :actor, :assignee, :last_event, :action

    def initialize(event:, actor:, assignee:, action:, last_event: false)
      raise ArgumentError, "Invalid action: #{action.inspect}" unless VALID_ACTIONS.include?(action)

      @event = event
      @actor = actor
      @assignee = assignee
      @action = action
      @last_event = last_event
    end

    def event_at
      event.created_at
    end

    def padding
      @last_event ? 0 : 3
    end

    def test_selector
      "alert-timeline-event-#{action}"
    end

    def self_assignment?
      actor.id == assignee.id
    end

    def action_text
      if self_assignment?
        action == :assigned ? "self-assigned this" : "removed their assignment"
      else
        action.to_s
      end
    end
  end
end
