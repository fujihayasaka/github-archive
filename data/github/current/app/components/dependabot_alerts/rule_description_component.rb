# typed: strict
# frozen_string_literal: true

module DependabotAlerts
  class RuleDescriptionComponent < ApplicationComponent
    sig { params(rule: VulnerabilityAlertRule).void }
    def initialize(rule:)
      @rule = rule
    end

    PRESET_RULE_NAMES = T.let([
      VulnerabilityAlertRule::LOW_IMPACT_RULE_NAME,
      VulnerabilityAlertRule::MALWARE_PACKAGE_RULE_NAME,
    ].freeze, T::Array[String])

    LOW_IMPACT_DESCRIPTION = T.let(<<~DESC.squish, String)
      In a developer (non-production or runtime) environment, these alerts are unlikely to be exploitable
      or have limited effect like slow builds or long-running tests.
    DESC

    sig { returns(T::Boolean) }
    def default_rule?
      @rule.target_type == "global" && @rule.target_id == 0
    end

    sig { returns(T::Boolean) }
    def preset_rule?
      default_rule? && PRESET_RULE_NAMES.include?(@rule.name)
    end

    sig { returns(T::Boolean) }
    def low_impact_rule?
      default_rule? && @rule.name == VulnerabilityAlertRule::LOW_IMPACT_RULE_NAME
    end

    sig { returns(T::Boolean) }
    def malware_package_rule?
      default_rule? && @rule.name == VulnerabilityAlertRule::MALWARE_PACKAGE_RULE_NAME
    end

    sig { returns(String) }
    def description
      if low_impact_rule?
        LOW_IMPACT_DESCRIPTION
      else
        "Matches "
      end
    end

    sig { returns(T::Hash[String, String]) }
    def conditions
      rule_conditions = {}
      @rule.conditions.sort_by(&:first).each do |key, values|
        case key
        when "cwe"
          cwes = values.map { |value| value.sub("CWE-", "") }
          rule_conditions[key] = cwes.map(&:to_i).sort.join(",")
        when "ecosystem"
          rule_conditions[key] = values.map { |value| AdvisoryDB::Ecosystems.label(value) }.join(",")
        when "classification"
          rule_conditions[key] = values.map { |value| value == "general" ? "vulnerability" : value }.join(",")
        else
          rule_conditions[key] = values.join(",")
        end
      end
      rule_conditions
    end
  end
end
