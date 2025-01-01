# typed: strict
# frozen_string_literal: true

module DependabotAlerts
  class RuleTargetAlertsTextboxComponent < ApplicationComponent
    sig { returns VulnerabilityAlertRule }
    attr_reader :rule

    sig { params(rule: VulnerabilityAlertRule).void }
    def initialize(rule:)
      @rule = rule
    end

    sig { returns(T::Hash[String, String]) }
    def conditions
      rule_conditions = {}
      rule.conditions.sort_by(&:first).each do |key, values|
        case key
        when "cwe"
          cwes = values.map { |value| value.sub("CWE-", "") }
          rule_conditions[key] = cwes.map(&:to_i).sort.join(",")
        when "ecosystem"
          rule_conditions[key] = values.map { |value| AdvisoryDB::Ecosystems.label(value) }.join(",")
        else
          rule_conditions[key] = values.join(",")
        end
      end
      rule_conditions
    end

    sig { returns(String) }
    def target_alerts
      target_alerts = ""
      conditions.each_with_index do |(key, value), index|
        target_alerts += "#{key}:#{value}"
        target_alerts += " " unless index == conditions.size - 1
      end
      target_alerts
    end
  end
end
