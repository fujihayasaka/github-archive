# typed: true
# frozen_string_literal: true

# Hydro event subscriptions for custom copilot events
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("custom_copilot.event") do |payload|
    message = {
      custom_copilot_id: payload[:custom_copilot_id],
      custom_copilot_number: payload[:custom_copilot_number],
      total_size: payload[:total_size],
      user_analytics_tracking_id: payload[:user_analytics_tracking_id],
      action: payload[:action],
      instructions_size: payload[:instructions_size],
      errors: payload[:errors],
      request_id: payload[:request_id],
      visibility: payload[:visibility],
      owner_type: payload[:owner_type],
      owner_id: payload[:owner_id],
      data: payload[:data].to_json,
      resource_count: payload[:resource_count],
    }

    publish(message, schema: "copilot.v0.CustomCopilotEvent")
  end

  subscribe("custom_copilot.restricted_event") do |payload|
    message = {
      custom_copilot_id: payload[:custom_copilot_id],
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
      owner_type: payload[:owner_type],
      owner_id: payload[:owner_id],
      data: payload[:data].to_json,
      resource_count: payload[:resource_count],
    }

    publish(message, schema: "copilot.v0.RestrictedCustomCopilotEvent")
  end

  # Note that generic event callers need to do all the work to format the payload correctly.
  subscribe("custom_copilot.generic_event") do |payload|
    publish(payload, schema: "copilot.v0.CustomCopilotEvent")
  end
end
