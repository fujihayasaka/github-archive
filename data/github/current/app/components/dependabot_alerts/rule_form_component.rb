# typed: strict
# frozen_string_literal: true

module DependabotAlerts
  class RuleFormComponent < ApplicationComponent
    extend T::Sig

    sig { returns T.nilable(Repository) }
    attr_reader :current_repository

    sig { returns T.nilable(Organization) }
    attr_reader :current_organization

    sig { returns VulnerabilityAlertRule }
    attr_reader :rule

    sig do
      params(
        view_name: String,
        dependabot_alert_cwe_suggestions: String,
        dependabot_alert_scope_suggestions: String,
        dependabot_alert_severity_suggestions: String,
        dependabot_alert_package_suggestions_path: String,
        dependabot_alert_manifest_suggestions_path: T.nilable(String),
        dependabot_alert_ecosystem_suggestions_path: String,
        dependabot_alert_cve_id_suggestions_path: String,
        dependabot_alert_ghsa_id_suggestions_path: String,
        local_search_hotkey: String,
        rule: VulnerabilityAlertRule,
        current_repository: T.nilable(Repository),
        current_organization: T.nilable(Organization),
        rule_criteria: String,
      ).void
    end
    def initialize(
      view_name:,
      dependabot_alert_cwe_suggestions:,
      dependabot_alert_scope_suggestions:,
      dependabot_alert_severity_suggestions:,
      dependabot_alert_package_suggestions_path:,
      dependabot_alert_manifest_suggestions_path:,
      dependabot_alert_ecosystem_suggestions_path:,
      dependabot_alert_cve_id_suggestions_path:,
      dependabot_alert_ghsa_id_suggestions_path:,
      local_search_hotkey:,
      rule:,
      current_repository: nil,
      current_organization: nil,
      rule_criteria: ""
    )
      if current_repository.nil? && current_organization.nil?
        raise ArgumentError, "either current_repository or current_organization must be provided"
      elsif current_repository.present? && current_organization.present?
        raise ArgumentError, "only one of current_repository or current_organization can be provided"
      end

      @view_name = view_name
      @dependabot_alert_cwe_suggestions = dependabot_alert_cwe_suggestions
      @dependabot_alert_scope_suggestions = dependabot_alert_scope_suggestions
      @dependabot_alert_severity_suggestions = dependabot_alert_severity_suggestions
      @dependabot_alert_package_suggestions_path = dependabot_alert_package_suggestions_path
      @dependabot_alert_manifest_suggestions_path = dependabot_alert_manifest_suggestions_path
      @dependabot_alert_ecosystem_suggestions_path = dependabot_alert_ecosystem_suggestions_path
      @dependabot_alert_cve_id_suggestions_path = dependabot_alert_cve_id_suggestions_path
      @dependabot_alert_ghsa_id_suggestions_path = dependabot_alert_ghsa_id_suggestions_path
      @local_search_hotkey = local_search_hotkey
      @rule = rule
      @rule_criteria = rule_criteria
      @current_repository = current_repository
      @current_organization = current_organization
    end

    sig { returns(T.any(Repository, User)) }
    def enablement_target
      T.must_because(current_repository || current_organization) { "Presence checked during initialization" }
    end

    sig { returns(String) }
    def form_url
      if @current_repository.present?
        if new_rule_page?
          create_dependabot_rule_path
        else
          update_dependabot_rule_path(user_id: @current_repository.owner, repository: @current_repository, rule_id: @rule)
        end
      else
        if new_rule_page?
          settings_org_create_dependabot_rule_path
        else
          settings_org_update_dependabot_rule_path(organization_id: current_organization, id: rule.id)
        end
      end
    end

    sig { returns(Symbol) }
    def request_type
      new_rule_page? ? :post : :put
    end

    sig { returns(String) }
    def submit_button_label
      new_rule_page? ? "Create Dependabot rule" : "Update Dependabot rule"
    end

    sig { returns(String) }
    def submit_button_text
      new_rule_page? ? "Create rule" : "Save rule"
    end

    sig { returns(T::Boolean) }
    def new_rule_page?
      @view_name == "new"
    end

    sig { returns(T::Boolean) }
    def edit_rule_page?
      @view_name == "edit"
    end

    sig { returns(T.nilable(String)) }
    def alert_criteria_validation_message
      if rule.errors.added?(:query_string, :blank)
        "Enter alert metadata"
      elsif rule.errors.added?(:query_string, :invalid)
        rule.errors.where(:query_string, :invalid).first.message
      elsif rule.errors[:conditions].any?
        rule.errors[:conditions].first
      end
    end

    sig { returns(T::Boolean) }
    def alert_criteria_invalid?
      rule.errors.include?(:query_string) || @rule.errors.include?(:conditions)
    end

    sig { returns(T.nilable(String)) }
    def rules_validation_message
      if rule.errors.added?(:actions, :blank)
        "At least one selection is required"
      elsif rule.errors.added?(:actions, :alert_actions_invalid_auto_dismiss)
        "Select an option for rule 'Dismiss alerts'"
      end
    end

    sig { returns(T.nilable(String)) }
    def enforcement_validation_message
      if rule.errors.added?(:enablement_behavior, "is not included in the list")
        "Select a valid state option"
      end
    end

    sig { returns(String) }
    def attribute_names_with_errors
      # listed in the same order as the fields are shown on the form
      possible_attributes = %i(name query_string conditions enablement_behavior actions)
      invalid_attributes = possible_attributes.select { |attribute| @rule.errors.include?(attribute) }
      attributes = invalid_attributes.map { |attribute| nice_attribute_name(attribute) }.uniq

      DependabotAlerts::RuleErrorDescriptionComponent.new(attributes).render_in(self.view_context)
    end

    sig { params(attribute: Symbol).returns(String) }
    def nice_attribute_name(attribute)
      case attribute
      when :name then "Rule name"
      when :query_string then "Target alerts"
      when :conditions then "Target alerts"
      when :actions then "Rules"
      when :enablement_behavior then "State"
      else ""
      end
    end

    sig { returns(T::Boolean) }
    def org_view?
      current_organization.present?
    end
  end
end
