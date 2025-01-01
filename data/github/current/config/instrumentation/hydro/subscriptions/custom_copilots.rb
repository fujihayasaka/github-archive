# typed: true
# frozen_string_literal: true

# Hydro event subscriptions for custom copilot events
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("custom_copilot.event") do |payload|
    message = {
      custom_copilot_id: payload[:custom_copilot_id],
      custom_copilot_uuid: payload[:custom_copilot_uuid],
      total_size: payload[:total_size],
      user_analytics_tracking_id: payload[:user_analytics_tracking_id],
      action: payload[:action],
      instructions_size: payload[:instructions_size],
    }

    publish(message, schema: "copilot.v0.CustomCopilotEvent")
  end

  subscribe("custom_copilot.restricted_event") do |payload|
    message = {
      custom_copilot_id: payload[:custom_copilot_id],
      custom_copilot_uuid: payload[:custom_copilot_uuid],
      total_size: payload[:total_size],
      user_analytics_tracking_id: payload[:user_analytics_tracking_id],
      action: payload[:action],
      name: payload[:name],
      description: payload[:description],
      resources: payload[:resources],
      instructions: payload[:instructions],
      instructions_size: payload[:instructions_size],
    }

    publish(message, schema: "copilot.v0.RestrictedCustomCopilotEvent")
  end
end
