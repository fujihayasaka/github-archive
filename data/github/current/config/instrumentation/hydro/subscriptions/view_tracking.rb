# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("browser.view_rendered") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:client][:user]),
      name: payload[:name],
    }

    publish(message, schema: "github.v1.ViewRendered")
  end
end
