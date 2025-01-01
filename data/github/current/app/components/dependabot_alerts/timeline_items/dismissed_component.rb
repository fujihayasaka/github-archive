# typed: true
# frozen_string_literal: true

module DependabotAlerts::TimelineItems
  class DismissedComponent < ApplicationComponent
    attr_reader :event, :actor, :last_event

    def initialize(event:, actor:, last_event:)
      @event = event
      @actor = actor
      @last_event = last_event
    end

    def dismissed_at
      event.created_at
    end

    def dismiss_reason
      RepositoryVulnerabilityAlert::DISMISS_REASONS.fetch(event.reason).downcase
    end

    def show_event_comment?
      event.event_comment.present?
    end

    def padding
      if @last_event || show_event_comment?
        0
      else
        3
      end
    end
  end
end
