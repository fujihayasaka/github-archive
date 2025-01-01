# typed: strict
# frozen_string_literal: true

module DependabotAlerts
  class RuleDescriptionComponent < ApplicationComponent
    extend T::Sig

    sig { params(rule: VulnerabilityAlertRule).void }
    def initialize(rule:)
      @rule = rule
    end

    sig { returns(T::Boolean) }
    def default_rule?
      @rule.target_type == "global" && @rule.target_id == 0
    end

    sig { returns(String) }
    def description
      if default_rule?
        <<~DESC.squish
          In a developer (non-production or runtime) environment, these alerts are unlikely to be exploitable
          or have limited effect like slow builds or long-running tests.
        DESC
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
        else
          rule_conditions[key] = values.join(",")
        end
      end
      rule_conditions
    end
  end
end
