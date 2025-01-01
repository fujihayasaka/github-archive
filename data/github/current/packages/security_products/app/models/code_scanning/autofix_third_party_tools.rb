# typed: true
# frozen_string_literal: true

module CodeScanning
  class AutofixThirdPartyTools
    POLICY_NAME = "third_party_tools"

    def self.is_supported_tool?(tool_name)
      supported_tools = Turboscan::SuggestedFix::ENABLED_TOOLS - [CodeScanning::AutofixCodeql::CODEQL_TOOL_NAME]
      supported_tools.include?(tool_name)
    end

    def self.enabled_for_repo?(repo)
      repo_settings_configurable?(repo) && CodeScanningRepositoryConfig.new(repo).code_scanning_autofix_third_party_tools_settings_enabled?
    end

    def self.enabled_for_org?(org)
      org_settings_configurable?(org) && CodeScanningOrganizationConfig.new(organization: org).code_scanning_autofix_third_party_tools_settings_enabled?
    end

    def self.allowed_by_business?(business)
      policy_available?(business) && business.code_scanning_autofix_third_party_tools_policy_allowed?
    end

    def self.repo_settings_configurable?(repository)
      return false unless CodeScanning::Autofix.available_in_environment?
      return false unless CodeSecurity::Features::AdvancedSecurityHelper.code_security_features_usable?(repository:)
      return enabled_for_org?(repository.owner) if repository.owner.is_a?(Organization)

      true
    end

    def self.org_settings_configurable?(organization)
      return false unless CodeScanning::Autofix.available_in_environment?

      billable_entity = AdvancedSecurityLicense.billable_entity(organization)
      return billable_entity.code_scanning_autofix_third_party_tools_policy_allowed? if billable_entity.is_a?(Business)

      true
    end

    def self.policy_available?(business)
      return false unless CodeScanning::Autofix.available_in_environment?

      business.advanced_security_purchased?
    end

    def self.changelog_url
      "https://gh.io/copilot-autofix-for-eslint"
    end
  end
end
