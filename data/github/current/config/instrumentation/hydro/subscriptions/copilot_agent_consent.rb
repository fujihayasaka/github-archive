# typed: true
# frozen_string_literal: true

# These are GlobalInstrumenter subscriptions that emit Hydro events related to
# GitHub Copilot agent consent on integration installations.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("integration_installation_agent_consent.create") do |payload|
    message = {
      installation: payload[:installation],
      integration: serializer.integration(payload[:integration]),
      agent_source: serializer.integration_agent_source(payload[:integration_agent_source]),
      sender: serializer.user(payload[:approver]),
      approved_at: payload[:approved_at],
    }

    publish(message, schema: "github.v1.IntegrationInstallationAgentConsentCreate")
  end

  subscribe("integration_installation_agent_consent.destroy") do |payload|
    message = {
      installation: payload[:installation],
      integration: serializer.integration(payload[:integration]),
      agent_source: serializer.integration_agent_source(payload[:integration_agent_source]),
      sender: serializer.user(payload[:approver]),
    }

    publish(message, schema: "github.v1.IntegrationInstallationAgentConsentDelete")
  end
end
