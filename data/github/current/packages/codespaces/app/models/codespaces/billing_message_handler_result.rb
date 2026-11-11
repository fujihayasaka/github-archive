# typed: true
# frozen_string_literal: true

module Codespaces
  class BillingMessageHandlerResult
    attr_reader :hydro_topic, :hydro_payload, :publisher

    GLOBAL_INSTRUMENTER = :global_instrumenter
    PUBLISH_RETRIER = :publish_retrier

    def initialize(hydro_topic:, hydro_payload:, publisher: GLOBAL_INSTRUMENTER)
      @hydro_topic = hydro_topic
      @hydro_payload = hydro_payload
      @publisher = publisher
    end

    def publish
      case publisher
      when PUBLISH_RETRIER
        # preferred for billing v next as it's more resilient
        result = Hydro::PublishRetrier.publish(hydro_payload, schema: hydro_topic)
        if result.error
          GitHub.logger.error(
            "Failed to publish usage message to billing platform",
            {
              hydro_topic: hydro_topic,
            }
          )
        end
      else
        # preferred for meuse as there's a subscriber in dotcom that transforms the data
        GlobalInstrumenter.instrument(hydro_topic, hydro_payload)
      end
    end
  end
end
