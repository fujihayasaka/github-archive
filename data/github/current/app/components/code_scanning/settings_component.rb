# typed: true
# frozen_string_literal: true

class CodeScanning::SettingsComponent < ApplicationComponent
  attr_reader :repository

  def initialize(repository:)
    @repository = repository
    @split_sku = !repository.advanced_security_products_bundled?
  end

  def severity
    CodeScanningRepositoryConfig.new(repository).code_scanning_severity_choice
  end

  def security_severity
    CodeScanningRepositoryConfig.new(repository).code_scanning_security_severity_choice
  end

  def show_protection_rules?
    code_security_features_usable?
  end

  def show_tools_section?
    code_security_features_usable? && prerequisite_setup_error.nil?
  end

  memoize def prerequisite_setup_error
    CodeScanning::Status.prerequisites_error_to_message(CodeScanning::Status.validate_prerequisites(repository, current_user), repository, current_user)
  end

  def rule_severities
    {
      Configurable::CodeScanningSeverities::SEVERITY_CHOICE_NONE => "None",
      Configurable::CodeScanningSeverities::SEVERITY_CHOICE_ERRORS => "Only errors",
      Configurable::CodeScanningSeverities::SEVERITY_CHOICE_ERRORS_AND_WARNINGS => "Errors and warnings",
      Configurable::CodeScanningSeverities::SEVERITY_CHOICE_ALL => "Any"
    }
  end

  def security_severities
    {
      Configurable::CodeScanningSeverities::SECURITY_SEVERITY_NONE => "None",
      Configurable::CodeScanningSeverities::SECURITY_SEVERITY_CRITICAL => "Only critical",
      Configurable::CodeScanningSeverities::SECURITY_SEVERITY_HIGH_OR_HIGHER => "High or higher",
      Configurable::CodeScanningSeverities::SECURITY_SEVERITY_MEDIUM_OR_HIGHER => "Medium or higher",
      Configurable::CodeScanningSeverities::SECURITY_SEVERITY_ALL => "Any"
    }
  end

  def show_autofix_section?
    autofix_codeql_settings_configurable? || autofix_third_party_tools_settings_configurable?
  end

  def autofix_codeql_settings_configurable?
    CodeScanning::AutofixCodeql.repo_settings_configurable?(repository)
  end

  def autofix_third_party_tools_settings_configurable?
    CodeScanning::AutofixThirdPartyTools.repo_settings_configurable?(repository)
  end

  def delegated_alert_dismissal_configurable?
    CodeScanning::AlertDismissalService.new(repository).can_enable?.value
  end

  def delegated_alert_dismissal_restricted?
    return false if repository.security_configuration&.code_scanning_delegated_alert_dismissal_not_set?

    repository.owner&.security_configurations_enabled? && repository.repository_security_configuration&.enforced?
  end

  private

  sig { returns(T::Boolean) }
  attr_reader :split_sku

  sig { returns(T::Boolean) }
  memoize def code_security_features_usable?
    CodeSecurity::Features::AdvancedSecurityHelper.code_security_features_usable?(repository: repository)
  end

  sig { returns(T::Boolean) }
  def cant_toggle_due_to_policy?
    product = SecurityProduct::CodeSecurity.new(repository)
    status = if product.enabled?
      product.can_disable?(actor: current_user, options: {})
    else
      product.can_enable?(actor: current_user, options: {})
    end

    return false unless status.error?
    [
      :code_security_not_allowed_by_policy,
      :code_security_restricted_by_enablement_policy,
    ].include? status.error
  end
end
