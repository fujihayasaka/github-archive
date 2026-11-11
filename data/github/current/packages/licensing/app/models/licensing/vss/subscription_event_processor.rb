# typed: true
# frozen_string_literal: true

module Licensing
  module Vss
    class SubscriptionEventProcessor
      AZURE_SERVICE_BUS_TOKEN_AUDIENCE = "https://servicebus.azure.net/"
      SUBSCRIPTION_EVENTS_TOPIC = "vss-subscription-events"

      def self.service_bus_config
        azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_environment
        token_provider_settings = GitHub::Azure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
        token_provider_settings.token_audience = AZURE_SERVICE_BUS_TOKEN_AUDIENCE
        token_provider = GitHub::Azure::ApplicationTokenProvider.new(
          GitHub.licensing_azure_spn_tenant_id,
          GitHub.licensing_azure_spn_client_id,
          GitHub.licensing_azure_spn_client_secret,
          token_provider_settings
        )

        {
          topic_name: SUBSCRIPTION_EVENTS_TOPIC,
          subscription_name: GitHub.vss_subscription_events_subscription_name,
          namespace: GitHub.vss_service_bus_namespace,
          token_provider: token_provider
        }
      end

      def initialize
        Failbot.push("codespace.name" => self.class.name)
      end

      def process(message)
        with_parsed_payload = T.let(false, T::Boolean)
        VssSubscriptionEvent.transaction do
          event = nil

          begin
            utf8_message = message.encoding == Encoding::UTF_8 ? message : message.force_encoding("UTF-8")
            event = VssSubscriptionEvent.create!(payload: message, parsed_payload: JSON.parse(utf8_message))
            with_parsed_payload = true
          rescue StandardError => e
            Failbot.report(e)
            event = VssSubscriptionEvent.create!(payload: message)
          end

          Licensing::VssSubscriptionEventProcessingJob.perform_later(event)
        end

        GitHub.dogstats.increment("licensing.vss_subscription_event_processing_job.created", tags: ["with_parsed_payload:#{with_parsed_payload}"])
      end
    end
  end
end
