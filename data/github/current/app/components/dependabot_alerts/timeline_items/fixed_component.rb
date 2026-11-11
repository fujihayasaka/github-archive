# typed: true
# frozen_string_literal: true

module DependabotAlerts::TimelineItems
  class FixedComponent < ApplicationComponent
    attr_reader :event, :last_event

    def initialize(event:, last_event:)
      @event = event
      @last_event = last_event
    end

    delegate :number, to: :pull_request, prefix: true, allow_nil: true

    memoize def alert
      event.repository_vulnerability_alert
    end

    def fixed_at
      event.created_at
    end

    memoize def pull_request
      event.pull_request
    end

    memoize def push
      event.push
    end

    def pull_request_path
      pull_request && helpers.pull_request_path(pull_request, alert.repository)
    end

    def pull_request_link_data_attributes
      return {} unless pull_request
      {
        hovercard_type: "pull_request",
        hovercard_url: "#{pull_request_path}/hovercard",
      }
    end
  end
end
