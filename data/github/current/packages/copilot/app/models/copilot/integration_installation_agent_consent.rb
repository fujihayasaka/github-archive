# typed: strict
# frozen_string_literal: true

module Copilot
  class IntegrationInstallationAgentConsent < ApplicationRecord::Domain::Copilot
    self.table_name = "integration_installation_agent_consents"
    self.strict_loading_by_default = true

    belongs_to :integration_installation, strict_loading: false
    belongs_to :integration_agent_source, class_name: "Copilot::IntegrationAgentSource"
    belongs_to :approver, class_name: "::User", foreign_key: :approver_id, strict_loading: false, inverse_of: :agent_consent_approvals

    validates :integration_installation_id, presence: true, uniqueness: true

    validates :integration_agent_source_id, presence: true

    validates :approver, presence: true
    validates :approved_at, presence: true
  end
end
