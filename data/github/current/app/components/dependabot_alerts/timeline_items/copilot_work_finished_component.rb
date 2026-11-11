# typed: true
# frozen_string_literal: true

module DependabotAlerts::TimelineItems
  class CopilotWorkFinishedComponent < ApplicationComponent
    attr_reader :event, :actor, :alert, :last_event

    def initialize(event:, actor:, alert:, last_event:)
      @event = event
      @actor = actor
      @alert = alert
      @last_event = last_event
    end

    def render?
      Dependabot.dependabot_alert_assign_to_copilot_for?(alert.repository)
    end

    def event_at
      event.created_at
    end

    def padding
      @last_event ? 0 : 3
    end
  end
end
