# typed: strict
# frozen_string_literal: true

# These are Hydro event subscriptions related to Azure Models.

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("azure_models_usage_details.update") do |payload|
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
end
