# typed: true
# frozen_string_literal: true

module CodeScanning
  class AiFindings
    POLICY_NAME = "ai_findings"

    def self.available_in_environment?
      GitHub.code_scanning_enabled? && !GitHub.enterprise?
    end

    def self.enabled_for_repo?(repo)
      repo_settings_configurable?(repo) && CodeScanningRepositoryConfig.new(repo).code_scanning_ai_findings_settings_enabled?
    end

    def self.enabled_for_org?(org)
      org_settings_configurable?(org) && CodeScanningOrganizationConfig.new(organization: org).code_scanning_ai_findings_settings_enabled?
    end

    def self.repo_settings_configurable?(repository)
      return false unless feature_flag_enabled_for?(repository) || feature_flag_enabled_for?(repository.owner)
      return false unless CodeScanning::AiFindings.available_in_environment?
      return false unless CodeSecurity::Features::AdvancedSecurityHelper.code_security_features_usable?(repository:)
      return enabled_for_org?(repository.owner) if repository.owner.is_a?(Organization)

      true
    end

    def self.org_settings_configurable?(organization)
      return false unless feature_flag_enabled_for?(organization)
      return false unless CodeScanning::AiFindings.available_in_environment?

      billable_entity = AdvancedSecurityLicense.billable_entity(organization)
      return billable_entity.code_scanning_autofix_policy_allowed? if billable_entity.is_a?(Business)

      true
    end

    def self.feature_flag_enabled_for?(actor)
      actor.feature_flag_enabled?(:code_scanning_ai_findings, default: false)
    end
  end
end
