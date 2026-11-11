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

  def value_param_name
    "value"
  end

  def autofix_limitations_documentation_url
    helpers.docs_url("code-security/responsible-use-autofix", ghec: true, fragment: "limitations-of-suggestions")
  end
end
