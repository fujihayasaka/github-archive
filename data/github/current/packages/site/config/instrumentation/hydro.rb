# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("analytics.lead_generation") do |payload|
    email_hash = Digest::SHA256.hexdigest(payload[:email])
    origin = payload[:origin] || "github.com"

    message = {
      email_hash:,
      origin:,
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor: serializer.user(payload[:actor]),
      source: payload[:source],
    }

    publish(message, schema: "github.analytics.v0.LeadGeneration")
  end
end
