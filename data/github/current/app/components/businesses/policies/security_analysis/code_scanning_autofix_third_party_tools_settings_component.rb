# typed: true
# frozen_string_literal: true

class Businesses::Policies::SecurityAnalysis::CodeScanningAutofixThirdPartyToolsSettingsComponent < ApplicationComponent
  attr_reader :business, :system_arguments

  TEST_SELECTOR = "businesses-policies-security-analysis-code-scanning-autofix-third-party-tools-settings"

  def initialize(business:, **system_arguments)
    @business = business
    @system_arguments = system_arguments
  end

  def autofix_third_party_tools_policy_allowed?
    business.code_scanning_autofix_third_party_tools_policy_allowed?
  end

  def value_param_name
    "value"
  end

  def autofix_limitations_documentation_url
    CodeScanning::AutofixThirdPartyTools.changelog_url
  end
end
