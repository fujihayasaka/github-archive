# typed: strict
# frozen_string_literal: true

module Copilot
  class IntegrationInstallationAgentConsent < ApplicationRecord::Domain::Copilot
    self.table_name = "integration_installation_agent_consents"
    self.strict_loading_by_default = true

    belongs_to :integration_installation, strict_loading: false
    belongs_to :integration_agent_source, class_name: "Copilot::IntegrationAgentSource", strict_loading: false
    belongs_to :approver, class_name: "::User", foreign_key: :approver_id, strict_loading: false, inverse_of: :agent_consent_approvals

    validates :integration_installation_id, presence: true, uniqueness: true

    validates :integration_agent_source_id, presence: true

    validates :approver, presence: true
    validates :approved_at, presence: true

    after_create_commit :emit_hydro_create_event
    before_destroy :capture_hydro_destroy_payload
    after_destroy_commit :emit_hydro_destroy_event

    private

    sig { void }
    def emit_hydro_create_event
      GlobalInstrumenter.instrument("integration_installation_agent_consent.create", hydro_event_payload)
    end

    sig { void }
    def capture_hydro_destroy_payload
      @hydro_destroy_payload = T.let(hydro_event_payload, T.nilable(T::Hash[Symbol, T.anything]))
    end

    sig { void }
    def emit_hydro_destroy_event
      payload = @hydro_destroy_payload
      return unless payload

      GlobalInstrumenter.instrument("integration_installation_agent_consent.destroy", payload)
    end

    sig { returns(T::Hash[Symbol, T.anything]) }
    def hydro_event_payload
      installation = T.must(integration_installation)
      target = installation.target
      target_type = if target.respond_to?(:organization?) && target.organization?
        :ORGANIZATION
      elsif installation.target_type == "Business"
        :BUSINESS
      else
        :USER
      end

      {
        installation: {
          id: installation.id,
          target_type: target_type,
          target_id: target.id,
          target_name: target.display_login,
          repository_selection: installation.repository_selection == "all" ? :ALL : :SELECTED,
        },
        integration: installation.integration,
        integration_agent_source: integration_agent_source,
        approver: approver,
        approved_at: approved_at,
      }
    end
  end
end
