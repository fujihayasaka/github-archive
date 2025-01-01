# typed: strict
# frozen_string_literal: true

# Hydro event subscriptions related to enterprise installation syncing.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("licensing.enterprise_installation_synced") do |payload|
    message = {
      business: serializer.business(payload[:business]),
      enterprise_installation: serializer.enterprise_installation(payload[:enterprise_installation]),
    }

    publish(message, schema: "github.licensing.v0.EnterpriseInstallationSynced")
  end
end
