# typed: true
# frozen_string_literal: true

class Businesses::Policies::SecurityAnalysis::GenericSecretsSettingsComponent < ApplicationComponent
  attr_reader :business, :system_arguments

  TEST_SELECTOR = "businesses-policies-security-analysis-generic-secrets-settings"

  def initialize(business:, **system_arguments)
    @business = business
    @system_arguments = system_arguments
  end

  def menu_items
    [
      GitHub::Menu::ButtonComponent.new(
        text: "Allowed",
        description: "All repositories with secret scanning may enable or disable AI detection to find additional patterns.",
        replace_text: "Allowed",
        checked: business.repo_admins_can_modify_generic_secrets_settings?,
        name: "all_orgs_repo_admins",
        value: "allowed",
        type: "submit",
      ),
      GitHub::Menu::ButtonComponent.new(
        text: "Not allowed",
        description: "All repositories with secret scanning may neither enable nor disable AI detection to find additional patterns.",
        replace_text: "Not allowed",
        checked: !business.repo_admins_can_modify_generic_secrets_settings?,
        name: "all_orgs_repo_admins",
        value: "not_allowed",
        type: "submit",
      ),
    ]
  end

  def repo_scope_text
    include_emus = AdvancedSecurity::Features::Business::AdvancedSecurity.new(business).feature_available_for_user_repositories?
    repo_scope_text = if include_emus
      "on organization-owned and user-owned repositories"
    else
      "on organization-owned repositories"
    end

    "By allowing this policy, repository admins can choose to enable or disable AI detection to find additional patterns #{repo_scope_text}. Note: changing this setting does not enable/disable AI detection."
  end
end
