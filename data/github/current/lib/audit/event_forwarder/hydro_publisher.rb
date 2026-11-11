# typed: true
# frozen_string_literal: true

module Audit
  class EventForwarder
    # Public: Publishes messages to the new Driftwood Audit Log services through Hydro.
    class HydroPublisher
      RETRY_DELAY = 0.2 # 200ms
      MAX_ATTEMPTS = 50 # We want to retry a lot here because audit-log data is quite important
      RETRYABLE_ERRORS = [
        ::Hydro::Sink::BufferOverflow,
        Kafka::DeliveryFailed
      ]

      DEFAULT_LOG = :GITHUB
      DEFAULT_SCHEMA = "audit_log.v2.AuditEntry"
      DOTCOM_TOPIC = "audit_log.v2.AuditEntry"
      GHES_TOPIC = "audit_log.v2.WebAuditEntry"
      API_REQUEST_TOPIC = "audit_log.v2.APIRequestAuditEntry"
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
        return false unless GitHub.driftwood_streaming_enabled? # Streaming can be disabled globally
        streaming_configured? # Are there any streams configured by the user?
      end

      def publish(action, payload, **options)
        return false unless should_publish?

        tags = ["event:#{action}", @role_tag]
        GitHub.dogstats.distribution_time("hydro_client.distribution_subscriber_time", tags: tags) do
          attempts = 0

          set_options(action, options) if options[:schema].nil?

          event_id = payload.fetch(:_document_id)
          event_time = Audit.milliseconds_to_time(payload.fetch(:@timestamp))

          hydro_message = {
            action: action,
            document: payload.to_json,
            document_id: event_id,
            event_time: event_time,
            audit_log: DEFAULT_LOG
          }

          begin
            result = GitHub.hydro_publisher.publish(hydro_message, **options)
            raise(result.error) unless result.success?
          rescue ::Hydro::Sink::Error, Kafka::DeliveryFailed => e
            attempts += 1
            if retry_publish_on?(e, attempts)
              if FeatureFlag.vexi.enabled?(:audit_log_job_fallback, default: false)
                if HydroAuditEntryJob.perform_later(hydro_message, **options)
                  report_fallback(e, schema: options[:schema], action: action)
                  return
                else
                  report_fallback_failed(schema: options[:schema], action: action)
                end
              end
              report_retry(e, schema: options[:schema], action: action)
              sleep @retry_delay
              retry
            end
          end

          if !result.success?
            report_error(result.error, schema: options[:schema], action: action)
          end

          result
        end
      end

      private

      def retry_publish_on?(error, tries)
        RETRYABLE_ERRORS.any? { |c| error.kind_of?(c) } && tries < @max_attempts
      end

      def report_fallback(error, schema:, action:)
        GitHub.dogstats.increment(
          "hydro.audit_event_forwarder.publish_fallback",
          tags: [
            "schema:#{schema}",
            "error:#{error.class.name.underscore}",
            "action:#{action}"
          ]
        )
      end

      def report_fallback_failed(schema:, action:)
        GitHub.dogstats.increment(
          "hydro.audit_event_forwarder.publish_fallback_failed",
          tags: [
            "schema:#{schema}",
            "action:#{action}"
          ]
        )
      end

      def report_retry(error, schema:, action:)
        GitHub.dogstats.increment(
          "hydro.audit_event_forwarder.publish_retry",
          tags: [
            "schema:#{schema}",
            "error:#{error.class.name.underscore}",
            "action:#{action}"
          ]
        )
      end

      def report_error(error, schema:, action:)
        GitHub.dogstats.increment(
          "hydro_client.publish_error",
          tags: [
            "schema:#{schema}",
            "error:#{error.class.name.underscore}",
            "action:#{action}"
          ],
        )

        Failbot.report(error, {
          schema: schema,
        })
      end

      def set_options(action, options)
        if GitHub.enterprise?
          topic = GHES_TOPIC
          format_version = ::Hydro::Topic::FormatVersion::V2
        elsif action == "api.request"
          topic = API_REQUEST_TOPIC
          format_version = ::Hydro::Topic::FormatVersion::V2
        else
          topic = DOTCOM_TOPIC
          format_version = ::Hydro::Topic::FormatVersion::V1
        end

        options[:schema] = DEFAULT_SCHEMA
        options[:topic] = topic
        options[:topic_format_options] ||= {}
        options[:topic_format_options][:format_version] = format_version
      end

      def streaming_configured?
        # Throttle check to verify whether there's any configured streams every EXPIRY_INTERVAL
        return @configured if Time.now < @next_check
        @next_check = Time.now + EXPIRY_INTERVAL
        @configured = AuditLogStreamConfiguration.exists?
      end
    end
  end
end
