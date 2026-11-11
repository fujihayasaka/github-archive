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

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("licensing.enterprise_installation_deleted") do |payload|
    # We only emit right now if `owner_type` is "Business". If it's not, return and no-op.
    # (`owner_type` can be "Business" or "User", and FYI `owner` can be an Organization when `owner_type` is "User", so do beware of that if we ever try to use it :O)
    if payload[:owner_type] == "Business"
      message = {
        business: serializer.business(payload[:owner]),
        enterprise_installation: serializer.enterprise_installation(payload[:enterprise_installation]),
      }

      publish(message, schema: "github.licensing.v0.EnterpriseInstallationDeleted")
    end
  end
end
