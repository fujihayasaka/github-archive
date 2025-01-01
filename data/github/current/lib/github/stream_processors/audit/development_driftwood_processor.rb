# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Audit
      # !!! DEVELOPMENT (bpdev, codespace) ENVIRONMENT SPECIFIC !!!
      #
      # A Stream processor for listening to the global AuditEntry topic
      # and publishing.
      # Note that this stream processor is a workaround to enable audit logs stream into kafka-lite
      # that are generated outside github, and is not how data flow works for dotcom audit logs
      class DevelopmentDriftwoodProcessor < BaseProcessor
        DEFAULT_GROUP_ID = "development_driftwood_processor"
        DEFAULT_SUBSCRIBE_TO = /audit_log\.v2\.AuditEntry\Z/

        options[:max_bytes_per_partition] = 0.5.megabytes
        options[:max_wait_time] = 0.5.seconds
        options[:min_bytes] = 1.bytes
        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds
        options[:start_from_beginning] = false

        # Public: Configure the Hydro processor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        end

        # Public: Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          raise "development only" if Rails.env.production?
          raise "use EnterpriseDriftwoodProcessor in GHES instead" if GitHub.single_business_environment?

          action = message.value.dig(:action, :value)
          document = JSON.parse(message.value.dig(:document, :value))
          document_id = message.value.dig(:document_id, :value)
          event_time = message.value.dig(:event_time)

          return if action.starts_with?("git") && !AuditLogSettings.git_events_enabled?

          timestamp = ::Audit.time_to_milliseconds(Time.at(event_time[:seconds], event_time[:nanos], :nanosecond))

          finished_event = ::Audit::Service::PreparedData.new(input: document.merge({
            "_document_id" => document_id,
            "@timestamp" => timestamp,
            "action" => action,
            "created_at" => timestamp,
          })).build!

          GitHub.audit.log_payload(
            action: action,
            payload: finished_event.dup,
            on_error_behavior: :raise
          )
        end
      end
    end
  end
end
