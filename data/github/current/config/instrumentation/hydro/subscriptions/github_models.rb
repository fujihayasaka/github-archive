# typed: true
# frozen_string_literal: true

# Hydro events related to GitHub Models, also referred to as Project Neutron
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("github_models.api.authentication_result") do |payload|
    message = {
      user: serializer.user(payload[:user]),
      success: payload[:success],
      reason: payload[:reason]
    }

    publish(message, schema: "github.github_models.v0.ApiAuthenticationResult")
  end

  subscribe("github_models.feedback") do |payload|
    message = {
      user: payload[:user] ? serializer.user(payload[:user]) : nil,
      feedback_type: serializer.model_feedback_type(payload[:feedback_type]),
      feedback_choice: serializer.model_feedback_choices(payload[:feedback_choice]),
      content: payload[:content],
      model: payload[:model],
      can_be_contacted: payload[:can_be_contacted],
    }
    publish(message, schema: "github.github_models.v0.Feedback")
  end

  subscribe("github_models_usage_details.update") do |payload|
    next if GitHub.enterprise?

    serialized_user = serializer.user(payload[:user])

    message = {
      account_database_id: serialized_user[:id],
      account_type: serialized_user[:type],
      account_global_relay_id: serialized_user[:global_relay_id],
      signal: "github_models_usage",
      signal_update_data_json: payload[:auths_count].to_s,
      origin: "azure_models_usage_details",
    }

    publish(message, schema: "heliograph.v1.AccountSignalUpdate")
  end

  subscribe("github_models_gateway_log.create") do |payload|
    message = {
      actor: serializer.user(payload[:actor]),
      actor_primary_email: payload[:actor_primary_email],
      user_agent: payload[:user_agent],
      model: payload[:model],
      publisher: payload[:publisher],
      provider: payload[:provider],
      status: serializer.models_gateway_status(payload[:status_code]),
      success: payload[:status_code] == 200,
      status_code: payload[:status_code],
      rate_limit_type: payload[:rate_limit_type],
      rate_limit_window_seconds: payload[:rate_limit_window_seconds],
      provider_status_code: payload[:provider_status_code],
    }

    publish(message, schema: "github.github_models.v0.GatewayModelsLog")
  end
end
