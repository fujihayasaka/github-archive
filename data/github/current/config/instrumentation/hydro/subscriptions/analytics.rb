# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("analytics.event") do |payload|
    message = {
      request_context: serializer.request_context(
        GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)
      ),
      actor: serializer.user(payload[:actor]),
      action: payload[:action],
      category: payload[:category],
      label: payload[:label]
    }

    publish(message, schema: "github.analytics.v0.Event")
  end

  subscribe("browser.analytics.event") do |payload|
    message = {
      request_context: serializer.request_context(
        GitHub.context.to_hash,
        overrides: browser_request_context_overrides(payload)
      ),
      actor: serializer.user(payload[:client][:user]),
      action: payload[:action],
      category: payload[:category],
      label: payload[:label]
    }

    publish(message, schema: "github.analytics.v0.Event")
  end
end
