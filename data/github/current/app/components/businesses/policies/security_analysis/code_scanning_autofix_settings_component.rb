# typed: true
# frozen_string_literal: true

class Businesses::Policies::SecurityAnalysis::CodeScanningAutofixSettingsComponent < ApplicationComponent
  attr_reader :business, :system_arguments

  TEST_SELECTOR = "businesses-policies-security-analysis-code-scanning-autofix-settings"

  def initialize(business:, **system_arguments)
    @business = business
    @system_arguments = system_arguments
  end

  def autofix_policy_allowed?
    business.code_scanning_autofix_policy_allowed?
  end

  def policy_param_name
    "policy"
  end

  def autofix_limitations_documentation_url
    "#{GitHub.help_url(ghec_exclusive: true)}/code-security/code-scanning/managing-code-scanning-alerts/about-autofix-for-codeql-code-scanning#limitations-of-autofix-suggestions"
  end
end
