# typed: true
# frozen_string_literal: true

class CodeScanning::SettingsComponent < ApplicationComponent
  attr_reader :repository

  sig { params(repository: Repository).void }
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

  def show_prerequisite_setup_error_message?
    prerequisite_setup_error.present? && prerequisite_setup_error != :code_security_disabled
  end

  memoize def prerequisite_setup_error_message
    CodeScanning::Status.prerequisites_error_to_message(prerequisite_setup_error, repository, current_user)
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
  def disable_toggle_button?
    !code_security_toggle_allowed_by_policy? ||
    !code_security_toggle_allowed_by_security_configuration? ||
    !code_security_toggle_allowed_by_remaining_licenses?
  end

  # If some _non-policy_ error prevents toggling, the this method will return true.
  # This is true even if there would also be a policy error, but the non-policy error
  # is the first one encountered (since `status` only holds a single error).
  sig { returns(T::Boolean) }
  def code_security_toggle_allowed_by_policy?
    product = SecurityProduct::CodeSecurity.new(repository)
    status = if product.enabled?
      product.can_disable?(actor: current_user, options: {})
    else
      product.can_enable?(actor: current_user, options: {})
    end

    return true unless status.error?
    [
      :code_security_not_allowed_by_policy,
      :code_security_restricted_by_enablement_policy,
    ].exclude? status.error
  end

  sig { returns(T.nilable(T::Boolean)) }
  def code_security_toggle_allowed_by_security_configuration?
    return true if !repository.owner&.security_configurations_enabled?
    return true if repository.repository_security_configuration.nil?

    # At the moment security configurations must make a decision on code security.
    # There is no 'not set' option.
    # As a consequence, any enforced security configuration prevents toggling.
    !repository.repository_security_configuration.enforced?
  end

  sig { returns(T::Boolean) }
  def code_security_toggle_allowed_by_remaining_licenses?
    # Turning off can never be a license problem
    return true if CodeSecurity::Features::AdvancedSecurityHelper.code_security_enabled?(repository:)

    return false if repository&.owner&.code_security&.enabling_repo_exceeds_seat_allowance?(repository)

    true
  end

  sig { returns(T.nilable(String)) }
  def code_security_locked_toggle_message
    case
    when !code_security_toggle_allowed_by_security_configuration?
      "An enforced security configuration prevents changing the Code Security setting."
    when !code_security_toggle_allowed_by_policy?
      "An organization or enterprise policy prevents changing the Code Security setting."
    when !code_security_toggle_allowed_by_remaining_licenses?
      "Enabling Code Security requires more licenses than are currently available."
    else
      nil
    end
  end

  sig { returns(T.nilable(Symbol)) }
  memoize def prerequisite_setup_error
    CodeScanning::Status.validate_prerequisites(repository, current_user)
  end
end
