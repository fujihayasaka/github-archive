# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("external_identity.refresh_token") do |payload|
    external_identity = payload[:external_identity]
    refresh_token = payload[:refresh_token]
    client_ip = payload[:client_ip]
    cache_value = payload[:cache_value]

    message = {
      external_identity_id: external_identity&.id,
      refresh_token: refresh_token,
      client_ip: client_ip,
      cache_value: cache_value,
    }

    publish(message, schema: "github.external_identity.v0.RefreshToken")
  end

  subscribe("external_identity.enterprise_created") do |payload|
    message = {
      enterprise_id: payload[:enterprise_id],
      name: payload[:name],
      website: payload[:website],
      slug: payload[:slug],
      shortcode: payload[:shortcode],
      admin_email: payload[:admin_email],
      enterprise_type: payload[:enterprise_type],
      seat_plan_type: payload[:seat_plan_type],
      subscription_id: payload[:subscription_id],
      tp_id: payload[:tp_id],
      billing_street: payload[:billing_street],
      billing_city: payload[:billing_city],
      billing_state: payload[:billing_state],
      billing_zip: payload[:billing_zip],
      billing_country: payload[:billing_country],
      copilot_max_seats: payload[:copilot_max_seats]
    }

    publish(message, schema: "github.external_identity.v0.EnterpriseCreated")
  end
end
