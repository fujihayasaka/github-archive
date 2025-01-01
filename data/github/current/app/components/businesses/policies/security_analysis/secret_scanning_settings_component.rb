# typed: true
# frozen_string_literal: true

class Businesses::Policies::SecurityAnalysis::SecretScanningSettingsComponent < ApplicationComponent
  attr_reader :business, :system_arguments

  TEST_SELECTOR = "businesses-policies-security-analysis-secret-scanning-settings"

  def initialize(business:, **system_arguments)
    @business = business
    @system_arguments = system_arguments
  end

  def validity_checks_available?
    SecretScanning::Features::Business::ValidityChecks.new(@business).feature_available?
  end

  def menu_items
    [
      GitHub::Menu::ButtonComponent.new(
        text: "Allowed",
        description: "Repository admins can enable or disable secret scanning and push protection.",
        replace_text: "Allowed",
        checked: business.repo_admins_can_modify_secret_scanning_settings?,
        name: "all_repo_admins",
        value: "allowed",
        type: "submit",
      ),
      GitHub::Menu::ButtonComponent.new(
        text: "Not allowed",
        description: "Repository admins cannot enable or disable secret scanning and push protection.",
        replace_text: "Not allowed",
        checked: !business.repo_admins_can_modify_secret_scanning_settings?,
        name: "all_repo_admins",
        value: "not_allowed",
        type: "submit",
      ),
    ]
  end

  def repo_scope_text
    base = if validity_checks_available?
      "By allowing this policy, repository admins can choose to enable or disable secret scanning, push protection, and validity checks"
    else
      "By allowing this policy, repository admins can choose to enable or disable secret scanning and push protection"
    end

    include_emus = AdvancedSecurity::Features::Business::AdvancedSecurity.new(business).feature_available_for_user_repositories?
    if include_emus
      "#{base} on organization-owned and user-owned repositories"
    else
      "#{base} on organization-owned repositories"
    end
  end
end
