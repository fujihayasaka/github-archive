# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement::EnterpriseTestHelpers
  extend T::Sig

  def self.included(klass)
    # it is so common to want to setup enterprise mode with all security products
    # this can be overridden by calling `stub_enterprise_enablement` again
    klass.setup do |test|
      if GitHub.enterprise?
        test.stub_enterprise_enablement(true)
      end
    end
  end

  sig { params(state: T::Boolean).void }
  def stub_enterprise_enablement(state)
    stub_dependency_graph_and_dependents(state)
    GitHub.stubs(
      code_scanning_enabled?: state,
      actions_enabled?: state,
    )
  end

  sig { params(state: T::Boolean).void }
  def stub_dependency_graph_and_dependents(state)
    GitHub.stubs(
      dependency_graph_enabled?: state,
      dotcom_connection_enabled?: state,
      ghe_content_analysis_enabled?: state,
      dependabot_rules_enabled?: state,
      dependabot_enabled?: state,
    )
  end

  sig { params(state: T::Boolean).void }
  def stub_secret_scanning(state)
    GitHub.stubs(
      configuration_secret_scanning_enabled?: state,
    )
  end
end
