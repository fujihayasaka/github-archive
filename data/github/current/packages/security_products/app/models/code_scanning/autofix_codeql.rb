# typed: true
# frozen_string_literal: true

module CodeScanning
  class AutofixCodeql
    POLICY_NAME = "codeql"

    CODEQL_TOOL_NAME = "CodeQL"

    def self.enabled_for_repo?(repo)
      repo_settings_configurable?(repo) && CodeScanningRepositoryConfig.new(repo).code_scanning_autofix_settings_enabled?
    end

    def self.enabled_for_org?(org)
      org_settings_configurable?(org) && CodeScanningOrganizationConfig.new(organization: org).code_scanning_autofix_settings_enabled?
    end

    def self.allowed_by_business?(business)
      policy_available?(business) && business.code_scanning_autofix_policy_allowed?
    end

    def self.policy_available?(business)
      return false unless CodeScanning::Autofix.available_in_environment?

      business.advanced_security_purchased?
    end

    def self.repo_settings_configurable?(repository)
      return false unless CodeScanning::Autofix.available_in_environment?
      return false unless repository.advanced_security_usable?
      return enabled_for_org?(repository.owner) if repository.owner.is_a?(Organization)

      true
    end

    def self.org_settings_configurable?(organization)
      return false unless CodeScanning::Autofix.available_in_environment?

      billable_entity = AdvancedSecurityLicense.billable_entity(organization)
      return billable_entity.code_scanning_autofix_policy_allowed? if billable_entity.is_a?(Business)

      true
    end
  end
end
