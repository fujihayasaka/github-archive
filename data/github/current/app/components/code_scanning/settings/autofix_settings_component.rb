# typed: true
# frozen_string_literal: true

class CodeScanning::Settings::AutofixSettingsComponent < ApplicationComponent
  attr_reader :repository

  def initialize(repository:, autofix_codeql_settings_configurable:, autofix_third_party_tools_settings_configurable:)
    @repository = repository
    @autofix_codeql_settings_configurable = autofix_codeql_settings_configurable
    @autofix_third_party_tools_settings_configurable = autofix_third_party_tools_settings_configurable
  end

  def render?
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
    return false unless @repository.code_scanning_autofix_thirdparty_enabled?
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
end
