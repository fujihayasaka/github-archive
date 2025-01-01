# typed: strict
# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("billing.zuora_webhook") do |payload|
    message = {
      webhook_id: payload[:webhook].id,
    }

    publish(message, schema: "github.billing.v0.ZuoraWebhook", partition_key: payload[:webhook].account_id)
  end
end
