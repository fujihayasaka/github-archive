# typed: true
# frozen_string_literal: true

module DependabotAlerts::TimelineItems
  class AutoDismissedComponent < ApplicationComponent
    include RulesHelper

    attr_reader :alert, :event

    AUTO_DISMISSED_REASONS = %w[rule_created previous_rule_updated rule_enabled alert_created alert_updated
      previous_rule_deleted rule_updated previous_rule_disabled].freeze

    def initialize(alert:, event:, last_event: false)
      @alert = alert
      @event = event
      @last_event = last_event
    end

    delegate :number, to: :pull_request, prefix: true, allow_nil: true

    def auto_dismissed_at
      event.created_at
    end

    memoize def pull_request
      alert.create_pull_request
    end

    memoize def push
      alert.create_push
    end

    def comment
      target_rule = target_type.present? ? target_type + " rule" : "rule"

      case event.reason
      when "rule_created" then target_rule.capitalize + " created and "
      when "rule_enabled" then target_rule.capitalize + " enabled and "
      when "rule_updated" then target_rule.capitalize + " edited and "
      when "alert_created" then "Alert created and " + target_rule
      when "alert_updated" then "Alert metadata changed and " + target_rule
      when "previous_rule_deleted" then "Previous rule was deleted and " + target_rule
      when "previous_rule_disabled" then "Previous rule was disabled and " + target_rule
      when "previous_rule_updated" then "Previous rule was updated and " + target_rule
      end
    end

    def rule_applied
      if AUTO_DISMISSED_REASONS.include?(event.reason)
        " was applied"
      end
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

    def padding_bottom
      if @last_event || show_event_comment?
        0
      else
        3
      end
    end
  end
end
