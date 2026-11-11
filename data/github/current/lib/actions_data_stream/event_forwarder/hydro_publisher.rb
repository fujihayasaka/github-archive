# typed: true
# frozen_string_literal: true

module ActionsDataStream
  class EventForwarder
    # Public: Publishes messages to the Actions data stream core service through Hydro.
    class HydroPublisher
      RETRY_DELAY = 0.2
      MAX_ATTEMPTS = 50
      RETRYABLE_ERRORS = [
        ::Hydro::Sink::BufferOverflow,
        Kafka::DeliveryFailed
      ]

      DEFAULT_LOG = :GITHUB
      DEFAULT_SCHEMA = "actions_data_stream.v0.DataStreamEvent"
      DOTCOM_TOPIC = "actions_data_stream.v0.DataStreamEvent"
      EXPIRY_INTERVAL = 10.seconds

      def initialize(retry_delay: RETRY_DELAY, max_attempts: MAX_ATTEMPTS)
        @role_tag = "role:#{GitHub.role}"
        @retry_delay = retry_delay
        @max_attempts = max_attempts
        @next_check = 0
        @configured = false
      end

      def should_publish?
        return false unless GitHub.hydro_enabled?
        return true unless GitHub.enterprise? # Enabled for dotcom
        false
      end

      def publish(action, payload, **options)
        return false unless should_publish?

        tags = ["event:#{action}", @role_tag]
        GitHub.dogstats.distribution_time("hydro_client.distribution_subscriber_time", tags: tags) do
          attempts = 0

          set_options(action, options) if options[:schema].nil?

          hydro_message = {
            event_payload: payload
          }

          begin
            result = GitHub.hydro_publisher.publish(hydro_message, **options)
            raise(result.error) unless result.success?
          rescue ::Hydro::Sink::Error, Kafka::DeliveryFailed => e
            attempts += 1
            if retry_publish_on?(e, attempts)
              # TODO: consider durable retry via job queue, similar to https://github.com/github/github/blob/4fcce5f705a6904d8341a0ea45a18357f76ff54a/lib/audit/event_forwarder/hydro_publisher.rb#L62-L72
              report_retry(e, schema: options[:schema], action: action)
              sleep @retry_delay
              retry
            end
            report_error(e, schema: options[:schema], action: action)
            return false
          end

          result
        end
      end

      private

      def retry_publish_on?(error, tries)
        RETRYABLE_ERRORS.any? { |c| error.kind_of?(c) } && tries < @max_attempts
      end

      def report_retry(error, schema:, action:)
        # TODO: emit datadog metrics: see similar code in lib/audit/event_forwarder/hydro_publisher.rb
      end

      def report_error(error, schema:, action:)
        # TODO: emit datadog metrics: see similar code in lib/audit/event_forwarder/hydro_publisher.rb

        Failbot.report(error, {
          schema: schema,
        })
      end

      def set_options(action, options)
        options[:schema] = DEFAULT_SCHEMA
        options[:topic] = DOTCOM_TOPIC
      end

    end
  end
end
