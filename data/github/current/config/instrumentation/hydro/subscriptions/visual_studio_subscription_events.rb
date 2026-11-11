# typed: strict
# frozen_string_literal: true

# Hydro event subscriptions related to Visual Studio subscription events.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("visual_studio_subscription_event.create") do |payload|
    message = {
      event: {
        payload: payload[:options][:payload]
      },
    }
    parsed_event = ::Licensing::Vss::ParsedSubscriptionEvent.new(payload[:options][:payload])

    publish(
      message,
      schema: "github.licensing.v0.VisualStudioSubscriptionEventCreate",
      partition_key: parsed_event.subscription_id,
    )
  end
end
