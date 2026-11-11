# typed: true
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("copilot_user_feedback") do |payload|
    message = {
      request_id: payload[:request_id],
      hostname: payload[:hostname],
      path: payload[:path],
      subject: payload[:subject],
      rating:  serializer.copilot_feedback_rating(payload[:rating]),
      content: payload[:content],
      mode: payload[:mode],
    }
    publish(message, schema: "hydro.schemas.copilot.v0.CopilotFeedback")
  end
end
