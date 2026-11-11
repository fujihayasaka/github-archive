# typed: strict
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("copilot_notifications_inbox.telemetry") do |payload|
    message = {
      user_id: payload[:user].id,
      event: payload[:event],
      metadata: payload[:metadata].to_json,
      created_at: Time.now.utc,
    }

    publish(message, schema: "hydro.schemas.copilot_notifications_inbox.v0.Telemetry")
  end
end
