# typed: true
# frozen_string_literal: true

class CodeScanning::SettingsComponent < ApplicationComponent
  attr_reader :repository

  def initialize(repository:)
    @repository = repository
  end

  def severity
    CodeScanningRepositoryConfig.new(repository).code_scanning_severity_choice
  end

  def security_severity
    CodeScanningRepositoryConfig.new(repository).code_scanning_security_severity_choice
  end

  def show_protection_rules?
    repository.advanced_security_enabled? || repository.public?
  end

  def show_tools_section?
    show_protection_rules? && prerequisite_setup_error.nil?
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
end
