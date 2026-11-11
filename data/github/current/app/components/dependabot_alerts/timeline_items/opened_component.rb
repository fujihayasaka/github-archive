# typed: true
# frozen_string_literal: true

module DependabotAlerts::TimelineItems
  class OpenedComponent < ApplicationComponent
    attr_reader :alert

    def initialize(alert:, last_event: false)
      @alert = alert
      @last_event = last_event
    end

    delegate :number, to: :pull_request, prefix: true, allow_nil: true

    def opened_at
      alert.created_at
    end

    memoize def pull_request
      alert.create_pull_request
    end

    memoize def push
      alert.create_push
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
