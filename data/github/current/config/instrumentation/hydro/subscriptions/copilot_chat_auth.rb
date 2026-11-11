# typed: true
# frozen_string_literal: true

# Hydro event subscriptions for copilot chat authentication events
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("copilot.chat.auth.restricted") do |payload|
    message = {
      request_id: payload[:request_id],
      user_id: payload[:user_id],
      data: payload[:data].to_json,
    }.compact

    publish(message, schema: "hydro.schemas.copilot.v0.RestrictedCopilotChatAuthEvent")
  end
end
