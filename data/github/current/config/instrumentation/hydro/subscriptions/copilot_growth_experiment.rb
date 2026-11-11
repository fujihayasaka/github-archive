# typed: true
# frozen_string_literal: true

# Hydro event subscriptions for Copilot growth experiments
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("custom_gate.copilot_growth_experiment_assignment") do |payload|
    message = {
      request_context: serializer.request_context(GitHub.context.to_hash),
      actor_type: payload[:actor_type],
      actor_id: payload[:actor_id],
      actor_analytics_tracking_id: payload[:actor_analytics_tracking_id],
      experiment_name: payload[:experiment_name],
      variant: payload[:variant],
      has_copilot: payload[:has_copilot],
      assigned_at: payload[:assigned_at],
    }

    publish(message, schema: "hydro.schemas.github.copilot_growth_experiment.v0.ExperimentAssignment")
  end
end
