# typed: true
# frozen_string_literal: true

module DependabotAlerts::TimelineItems
  class AutoReopenedComponent < ApplicationComponent
    include RulesHelper

    attr_reader :event, :alert, :last_event

    def initialize(event:, alert:, last_event: false)
      @event = event
      @alert = alert
      @last_event = last_event
    end

    def auto_reopened_at
      event.created_at
    end

    def comment
      target_rule = target_type.present? ? target_type + " rule" : "rule"

      case event.reason
      when "alert_updated" then "Alert metadata changed and no longer matches criteria for " + target_rule
      when "previous_rule_deleted" then target_rule.capitalize + " deleted: "
      when "rule_disabled", "previous_rule_disabled" then target_rule.capitalize + " disabled: "
      when "previous_rule_updated" then target_rule.capitalize + " edited and alert no longer matches criteria for "
      end
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
