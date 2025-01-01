# typed: true
# frozen_string_literal: true

# Hydro event subscriptions for custom copilot events
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("custom_copilot.event") do |payload|
    message = {
      custom_copilot_id: payload[:custom_copilot_id],
      custom_copilot_uuid: payload[:custom_copilot_uuid],
      custom_copilot_number: payload[:custom_copilot_number],
      total_size: payload[:total_size],
      user_analytics_tracking_id: payload[:user_analytics_tracking_id],
      action: payload[:action],
      instructions_size: payload[:instructions_size],
      errors: payload[:errors],
      request_id: payload[:request_id],
      visibility: payload[:visibility],
      owner_type: payload[:owner].type,
      owner_id: payload[:owner].id
    }

    publish(message, schema: "copilot.v0.CustomCopilotEvent")
  end

  subscribe("custom_copilot.restricted_event") do |payload|
    message = {
      custom_copilot_id: payload[:custom_copilot_id],
      custom_copilot_uuid: payload[:custom_copilot_uuid],
      custom_copilot_number: payload[:custom_copilot_number],
      total_size: payload[:total_size],
      user_analytics_tracking_id: payload[:user_analytics_tracking_id],
      action: payload[:action],
      name: payload[:name],
      description: payload[:description],
      resources: payload[:resources],
      instructions: payload[:instructions],
      instructions_size: payload[:instructions_size],
      errors: payload[:errors],
      request_id: payload[:request_id],
      visibility: payload[:visibility],
      owner_type: payload[:owner].type,
      owner_id: payload[:owner].id
    }

    publish(message, schema: "copilot.v0.RestrictedCustomCopilotEvent")
  end
end
