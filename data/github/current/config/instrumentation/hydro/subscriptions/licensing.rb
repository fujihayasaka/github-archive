# typed: strict
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("business_licenses.snapshot") do |payload|
    business = payload[:business]

    message = ActiveRecord::Base.connected_to(role: :reading) do
      {
        request_context: serializer.request_context(GitHub.context.to_hash),
        business: serializer.business(business),
        max_enterprise_seats: business.seats,
        filled_enterprise_seats: business.consumed_enterprise_licenses,
        max_volume_seats: business.purchased_volume_licenses,
        filled_volume_seats: business.consumed_volume_licenses
      }
    end

    publish(message, schema: "github.billing.v0.LicenseSnapshot")
  end

  subscribe("external_identity.deprovision") do |payload|
    identity = payload[:identity]
    next unless identity.user&.is_enterprise_managed?

    message = {
      user_id: identity.user_id,
      business: serializer.business(identity.provider.business),
      suspended_at: identity.disabled_at,
    }
    publish(message, schema: "github.licensing.v0.EnterpriseManagedIdentitySuspended")
  end

  subscribe("external_identity.provision") do |payload|
    identity = payload[:identity]
    next unless identity.user&.is_enterprise_managed?

    message = {
      user_id: identity.user_id,
      business: serializer.business(identity.provider.business),
    }
    publish(message, schema: "github.licensing.v0.EnterpriseManagedIdentityUnsuspended")
  end
end
