# typed: strict
# frozen_string_literal: true

module DependabotAlerts
  class RuleCriteriaHelper
    sig { returns(VulnerabilityAlertRule) }
    attr_reader :rule

    sig { params(rule: VulnerabilityAlertRule).void }
    def initialize(rule)
      @rule = rule
    end

    sig { returns(String) }
    def form_value
      results = []
      VulnerabilityAlertRuleConditionsValidator::CONDITIONS.each do |filter|
        next if rule.conditions[filter].nil?

        case filter
        when "severity"
          rule.conditions["severity"].each do |severity|
            results << "severity:#{severity}"
          end
        when "manifest"
          rule.conditions["manifest"].each do |manifest|
            results << "manifest:#{manifest}"
          end
        when "cwe"
          rule.conditions["cwe"].each do |cwe|
            value = cwe.split("-")[1]
            results << "cwe:#{value}"
          end
        when "ecosystem"
          rule.conditions["ecosystem"].each do |ecosystem|
            results << "ecosystem:#{quoted_value(AdvisoryDB::Ecosystems.label(ecosystem))}"
          end
        when "epss"
          rule.conditions["epss"].each do |epss|
            results << "epss:#{epss}"
          end
        else
          rule.conditions[filter].each do |value|
            results << "#{filter}:#{value}"
          end
        end
      end

      return "" if results.empty?

      r = results.join(" ")
      r << " " # Add a space at the end so that the user doesn't modify an existing filter by mistake
    end

    private

    sig { params(value: String).returns(String) }
    def quoted_value(value)
      value.include?(" ") ? "\"#{value}\"" : value
    end
  end
end
