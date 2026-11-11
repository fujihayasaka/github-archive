# typed: strict
# frozen_string_literal: true

class Businesses::Policies::SecurityAnalysis::CodeScanningAiFindingsSettingsComponent < ApplicationComponent
  sig { returns(Business) }
  attr_reader :business

  sig { returns(T::Hash[Symbol, T.untyped]) }
  attr_reader :system_arguments

  TEST_SELECTOR = "businesses-policies-security-analysis-code-scanning-ai-findings-settings"

  sig { params(business: Business, system_arguments: T.untyped).void }
  def initialize(business:, **system_arguments)
    @business = business
    @system_arguments = system_arguments
  end

  sig { returns(T::Boolean) }
  def ai_findings_policy_allowed?
    business.code_scanning_ai_findings_policy_allowed?
  end

  sig { returns(String) }
  def value_param_name
    "value"
  end
end
