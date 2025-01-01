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
      Configurable::CodeScanning::SEVERITY_CHOICE_NONE => "None",
      Configurable::CodeScanning::SEVERITY_CHOICE_ERRORS => "Only errors",
      Configurable::CodeScanning::SEVERITY_CHOICE_ERRORS_AND_WARNINGS => "Errors and warnings",
      Configurable::CodeScanning::SEVERITY_CHOICE_ALL => "Any"
    }
  end

  def security_severities
    {
      Configurable::CodeScanning::SECURITY_SEVERITY_NONE => "None",
      Configurable::CodeScanning::SECURITY_SEVERITY_CRITICAL => "Only critical",
      Configurable::CodeScanning::SECURITY_SEVERITY_HIGH_OR_HIGHER => "High or higher",
      Configurable::CodeScanning::SECURITY_SEVERITY_MEDIUM_OR_HIGHER => "Medium or higher",
      Configurable::CodeScanning::SECURITY_SEVERITY_ALL => "Any"
    }
  end

  def autofix_settings_configurable?
    CodeScanning::Autofix.repo_settings_configurable?(repository)
  end

  def autofix_toggle_form_src
    repository_code_scanning_autofix_settings_path(repository.owner, repository)
  end

  def autofix_toggle_form_csrf_token
    authenticity_token_for(autofix_toggle_form_src)
  end

  def autofix_limitations_documentation_url
    "#{docs_base_url}/code-security/code-scanning/managing-code-scanning-alerts/about-autofix-for-codeql-code-scanning#limitations-of-autofix-suggestions"
  end

  private

  def docs_base_url
    owner = repository.owner
    GitHub.help_url(ghec_exclusive: owner.organization? && (owner.business || owner.business_plus?))
  end
end
