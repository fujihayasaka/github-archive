# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module RegistryMetadata
      class RmsVersionDeletedAuditProcessor < SingleMessageProcessor
        default_to_write_connection!

        DEFAULT_GROUP_ID = "rms_version_deleted_audit_processor"
        DEFAULT_SUBSCRIBE_TO = /registry_metadata\.v0\.VersionDeleted\Z/

        # See https://kafka.apache.org/documentation/#session.timeout.ms
        options[:session_timeout] = 60.seconds

        # This value must be greater than "session_timeout"
        # See https://github.com/zendesk/ruby-kafka#understanding-timeouts
        options[:socket_timeout] = 65.seconds

        # When the processor starts consuming from a partition for the first time and has no committed offsets,
        # `start_from_beginning` determines if should start from the beginning of the log (i.e. the oldest available messages)
        # or the end of the log (i.e. the newest available messages).
        #
        # This is the equivalent of the java client `auto.offset.reset` consumer config.
        # See: https://kafka.apache.org/documentation/#consumerconfigs_auto.offset.reset
        options[:start_from_beginning] = false

        # See https://kafka.apache.org/documentation/#fetch.min.bytes
        options[:min_bytes] = 1

        # Max amount of time the Kafka consumer will wait to fetch data.
        options[:max_wait_time] = 0.2.seconds

        # See https://kafka.apache.org/documentation/#max.partition.fetch.bytes
        options[:max_bytes_per_partition] = 1.megabyte

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
          instrument(message)
        end

        private

        def instrument(message)
          actor = ::PackageRegistry::Instrumentation.get_actor(actor_id: message.value.dig(:actor_id), actor_type: message.value.dig(:actor_type))

          owner_id = message.value.dig(:owner_id)
          owner_name = message.value.dig(:package, :display_login)
          ecosystem = message.value.dig(:package, :ecosystem)
          package_id = message.value.dig(:package, :id)
          package_name = message.value.dig(:package, :name)
          version_id = message.value.dig(:version, :id)
          version_sha = message.value.dig(:version, :original_name).present? ? message.value.dig(:version, :original_name) : message.value.dig(:version, :name)
          storage_bytes = message.value.dig(:storage_bytes)
          actor_type = message.value.dig(:actor_type)
          user_agent = message.value.dig(:user_agent)

          deleted_time_seconds = message.value.dig(:deleted_at, :seconds)
          deleted_time_nanos = message.value.dig(:deleted_at, :nanos)
          epoch_micros = deleted_time_nanos / 10**3
          deleted_time = Time.at(deleted_time_seconds, epoch_micros).to_s

          return message.skip("missing actor") if actor.nil?

          ::PackageRegistry::Instrumentation.v2_package_version_deleted(
              owner_id: owner_id,
              owner_name: owner_name,
              ecosystem: ecosystem,
              package_id: package_id,
              package_name: package_name,
              version_id: version_id,
              version_sha: version_sha,
              storage_bytes: storage_bytes,
              actor_id: actor.id,
              actor: actor.login,
              user_agent: user_agent,
              deleted_time: deleted_time
          )
        end
      end
    end
  end
end
