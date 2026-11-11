# typed: strict
# frozen_string_literal: true

module User::AgentConsentDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { User }

  included do
    T.bind(self, T.class_of(User))

    has_many :agent_consent_approvals, class_name: "Copilot::IntegrationInstallationAgentConsent", inverse_of: :approver
  end
end
