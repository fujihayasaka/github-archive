# typed: true
# frozen_string_literal: true

module DependabotAlerts
  module RulesControllerHelper
    def suggestions_for_cwes
      CWE.pluck(:cwe_id, :name).map do |cwe_id, name|
        {
          value: cwe_id.split("-").second,
          name: cwe_id,
          description: name
        }
      end.to_json
    end

    def suggestions_for_scopes
      RepositoryVulnerabilityAlert.dependency_scopes.values.reverse.map { |scope| { value: scope } }.to_json
    end

    def suggestions_for_severities
      Vulnerability::SEVERITIES.reverse.map { |severity| { value: severity } }.to_json
    end

    def generate_rule_hash(target:, params:)
      rule = {
        target:,
        name: params[:vulnerability_alert_rule][:name].strip,
        query_string: params[:rule_criteria],
        actions: parse_actions(params),
        enablement_behavior: params[:vulnerability_alert_rule][:rule_behavior]
      }

      rule
    end

    def parse_actions(params)
      return nil unless contains_alert_actions?(params) || contains_update_actions?(params)

      {
        version: 1,
        alert_actions: alert_actions(params),
        update_actions: update_actions(params),
      }.compact
    end

    private

    def contains_alert_actions?(params)
      params.dig(:vulnerability_alert_rule, :auto_dismiss).to_i == 1
    end

    def contains_update_actions?(params)
      params.dig(:vulnerability_alert_rule, :create_pr).to_i == 1
    end

    def alert_actions(params)
      return nil unless contains_alert_actions?(params)

      {
        auto_dismiss: params[:vulnerability_alert_rule][:auto_dismiss_option],
      }
    end

    def update_actions(params)
      return nil unless contains_update_actions?(params)

      {
        create_pr: params[:vulnerability_alert_rule][:create_pr].to_i == 1
      }
    end
  end
end
