# typed: true
# frozen_string_literal: true

module Businesses::Policies::SecurityAnalysis
  class GhasCodeSecurityEnablementComponent < ApplicationComponent
    include BasePolicy

    attr_reader :business, :system_arguments

    TEST_SELECTOR = "businesses-policies-security-analysis-ghas-code-security-enablement"

    def initialize(business:, **system_arguments)
      @business = business
      @system_arguments = system_arguments
    end

    private

    sig { override.returns(String) }
    def policy_name
      "all_repo_admins"
    end

    sig { override.returns(T::Array[PolicyItem]) }
    def policy_options
      [
        PolicyItem.new(
          label: "Allowed",
          description: "Repository admins can enable or disable GitHub Code Security.",
          active: business.repo_admins_can_modify_code_security_enablement?,
          value: "allowed",
        ),
        PolicyItem.new(
          label: "Not allowed",
          description: "Repository admins cannot enable or disable GitHub Code Security.",
          active: !business.repo_admins_can_modify_code_security_enablement?,
          value: "not_allowed",
        )
      ]
    end
  end
end
