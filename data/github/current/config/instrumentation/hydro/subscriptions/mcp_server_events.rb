# typed: strict
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("mcp_server_event") do |payload|
    message = {
      action: payload[:action],
      user_analytics_tracking_id: payload[:user_analytics_tracking_id],
      mcp_server: payload[:mcp_server],
      status: payload[:status],
      context: payload[:context],
    }

    publish(message, schema: "hydro.schemas.copilot.v0.McpServerEvent")
  end
end
