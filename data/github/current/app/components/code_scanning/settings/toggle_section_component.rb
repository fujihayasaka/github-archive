# typed: true
# frozen_string_literal: true

class CodeScanning::Settings::ToggleSectionComponent < ApplicationComponent
  attr_reader :repository

  def initialize(
    repository:,
    autofix_codeql_settings_configurable:,
    autofix_third_party_tools_settings_configurable:,
    delegated_alert_dismissal_configurable:,
    delegated_alert_dismissal_restricted:
  )
    @repository = repository
    @autofix_codeql_settings_configurable = autofix_codeql_settings_configurable
    @autofix_third_party_tools_settings_configurable = autofix_third_party_tools_settings_configurable
    @delegated_alert_dismissal_configurable = delegated_alert_dismissal_configurable
    @delegated_alert_dismissal_restricted = delegated_alert_dismissal_restricted
  end

  def render?
    autofix_configurable? || delegated_alert_dismissal_configurable?
  end

  def autofix_configurable?
    autofix_codeql_settings_configurable? || autofix_third_party_tools_settings_configurable?
  end

  def autofix_codeql_settings_configurable?
    @autofix_codeql_settings_configurable
  end

  def autofix_codeql_toggle_form_src
    repository_code_scanning_autofix_settings_path(repository.owner, repository, policy: CodeScanning::AutofixCodeql::POLICY_NAME)
  end

  def autofix_codeql_toggle_form_csrf_token
    authenticity_token_for(autofix_codeql_toggle_form_src)
  end

  def autofix_codeql_limitations_documentation_url
    owner = repository.owner
    ghec = !!(owner.organization? && (owner.business || owner.business_plus?))
    helpers.docs_url("about-autofix", ghec: ghec, fragment: "limitations-of-suggestions")
  end

  def autofix_third_party_tools_settings_configurable?
    @autofix_third_party_tools_settings_configurable
  end

  def autofix_third_party_tools_toggle_form_src
    repository_code_scanning_autofix_settings_path(repository.owner, repository, policy: CodeScanning::AutofixThirdPartyTools::POLICY_NAME)
  end

  def autofix_third_party_tools_toggle_form_csrf_token
    authenticity_token_for(autofix_third_party_tools_toggle_form_src)
  end

  def autofix_third_party_tools_limitations_documentation_url
    CodeScanning::AutofixThirdPartyTools.changelog_url
  end

  def delegated_alert_dismissal_configurable?
    @delegated_alert_dismissal_configurable
  end

  def delegated_alert_dismissal_toggle_form_src
    repository_code_scanning_delegated_alert_dismissal_settings_path(repository.owner, repository)
  end

  def delegated_alert_dismissal_toggle_form_csrf_token
    authenticity_token_for(delegated_alert_dismissal_toggle_form_src)
  end

  def custom_role_url
    settings_org_role_assignments_path(repository.owner)
  end

  def delegated_alert_dismissal_restricted?
    @delegated_alert_dismissal_restricted
  end

  def delegated_alert_dismissal_enabled?
    CodeScanningRepositoryConfig.new(repository).code_scanning_delegated_alert_dismissal_settings_enabled?
  end
end
