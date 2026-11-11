# typed: true
# frozen_string_literal: true

module Businesses::Policies::SecurityAnalysis
  class DependabotRepositoryAccessComponent < ApplicationComponent
    include BasePolicy

    attr_reader :business, :system_arguments

    TEST_SELECTOR = "businesses-policies-security-analysis-dependabot-repository-access"

    def initialize(business:, **system_arguments)
      @business = business
      @system_arguments = system_arguments
    end

    def render?
      business.advanced_security_purchased?
    end

    sig { override.returns(String) }
    def policy_name
      "default_level"
    end

    sig do
      override
      .returns(T::Array[Businesses::Policies::SecurityAnalysis::BasePolicy::PolicyItem])
    end
    def policy_options
      [
        PolicyItem.new(
          label: "No policy",
          description: "Organizations choose their own Dependabot default repository access level.",
          active: current_access_level.nil?,
          value: "no_policy",
        ),
        PolicyItem.new(
          label: "Public",
          description: "Organizations allow Dependabot to only access public repositories.",
          active: current_access_level == "public",
          value: "public",
        ),
        PolicyItem.new(
          label: "Public + Internal",
          description: "Organizations allow Dependabot to access public and internal repositories.",
          active: current_access_level == "internal",
          value: "internal",
        ),
      ]
    end

    private

    sig { returns(T.nilable(String)) }
    def current_access_level
      business.dependabot_default_repository_access_raw
    end
  end
end
