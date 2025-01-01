# typed: true
# frozen_string_literal: true

module DependabotAlerts::TimelineItems
  class ReopenedComponent < ApplicationComponent
    attr_reader :event, :actor, :last_event

    def initialize(event:, actor:, last_event: false)
      @event = event
      @actor = actor
      @last_event = last_event
    end

    def reopened_at
      event.created_at
    end
  end
end
