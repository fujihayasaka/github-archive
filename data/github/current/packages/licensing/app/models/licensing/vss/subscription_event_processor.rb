# typed: true
# frozen_string_literal: true

module Licensing
  module Vss
    class SubscriptionEventProcessor
      def self.service_bus_config
        {
          topic_name: GitHub.vss_subscription_events_topic_name,
          subscription_name: GitHub.vss_subscription_events_subscription_name,
          connection_string: GitHub.vss_subscription_events_connection_string
        }
      end

      def initialize
        Failbot.push("codespace.name" => self.class.name)
      end

      def process(message)
        VssSubscriptionEvent.transaction do
          event = nil

          begin
            utf8_message = message.encoding == Encoding::UTF_8 ? message : message.force_encoding("UTF-8")
            event = VssSubscriptionEvent.create!(payload: message, parsed_payload: JSON.parse(utf8_message))
          rescue StandardError => e
            Failbot.report(e)
            event = VssSubscriptionEvent.create!(payload: message)
          end

          Licensing::VssSubscriptionEventProcessingJob.perform_later(event)
        end
      end
    end
  end
end
