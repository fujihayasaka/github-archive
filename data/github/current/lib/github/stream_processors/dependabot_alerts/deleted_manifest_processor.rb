# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module DependabotAlerts
      class DeletedManifestProcessor < BaseProcessor
        DEFAULT_GROUP_ID = "github-#{Rails.env}-dependabot_alerts-deleted_manifest_processor"
        DEFAULT_SUBSCRIBE_TO = /dependabot\.v0\.ManifestDeleted\Z/
        DEAD_LETTER_TOPIC = "dependabot.v0.ManifestDeleted.DeadLetter"

        include TransientErrorResiliency

        # This is the timeout used for determining if a given Kafka consumer has
        # failed or quit due to e.g. a deploy. Setting it to a lower value is NOT
        # recommended if your Hydro processor interacts with the database, since
        # Freno may wait up to 30 seconds when throttling writes. Processors that
        # do not interact with a database may lower this value to allow faster
        # consumer group rebalancing during deploys and processor failures.
        #
        # See https://kafka.apache.org/documentation/#session.timeout.ms
        options[:session_timeout] = 60.seconds

        # This value must be greater than "session_timeout"
        #
        # See https://github.com/zendesk/ruby-kafka#understanding-timeouts
        options[:socket_timeout] = 65.seconds

        # When the processor starts consuming from a partition for the first time and has no committed offsets,
        # `start_from_beginning` determines if should start from the beginning of the log (i.e. the oldest available messages)
        # or the end of the log (i.e. the newest available messages).
        #
        # This is the equivalent of the java client `auto.offset.reset` consumer config.
        # See: https://kafka.apache.org/documentation/#consumerconfigs_auto.offset.reset
        options[:start_from_beginning] = true

        # Other options you may want to set...
        #
        # This will cause the Kafka consumer to wait until there is at least a
        # given number of bytes available to fetch; but the consumer will wait
        # no longer than "max_wait_time" (described below). This allows the
        # processor to wait for a large enough batch of data. The default is
        # 1 byte, meaning data will be fetched as soon as it's available. Value
        # below is for example purposes only and not a recommendation; the default
        # value of 1 should be suitable for most cases.
        # See https://kafka.apache.org/documentation/#fetch.min.bytes
        # options[:min_bytes] = 1.kilobyte
        #
        # This is the maximum amount of time the Kafka consumer will wait to
        # fetch data. The default is 500ms (0.5.seconds). Value below is for
        # example purposes only and not a recommendation; the default value of
        # 500ms should be suitable for most cases.
        # options[:max_wait_time] = 1.second
        #
        # This is the maximum amount of data that will be fetched at a time. This
        # value is specified in bytes, so the number of distinct Hydro messages
        # fetched depends on the size of those messages. The default is 1MB. You
        # may want to consider lowering this if processing each batch of messages
        # is taking more than 60 seconds in order to ensure that your processor
        # shuts down in a timely manner during deploys.
        # See https://kafka.apache.org/documentation/#max.partition.fetch.bytes
        # options[:max_bytes_per_partition] = 100.kilobytes

        # Public: Configure the Hydro processor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.transient_error_max_retries = 10
          self.dead_letter_topic = DEAD_LETTER_TOPIC
        end

        # Clear any instance variable that hold message-specific information.
        # That way, we can collect metrics using these instance variables
        # without worrying that they leak between messages.
        set_callback :message, :before, :clear_state_before_message

        def clear_state_before_message
          @repository = nil
          @fixable_alerts = nil
        end

        # Public: Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          payload = message.value

          if reason = reason_to_skip_message(payload)
            message.skip(reason)
            return
          end

          push_id = payload.dig(:push_id, :value)
          pull_request_id = payload.dig(:pull_request_id, :value)

          @fixable_alerts.find_each do |alert|
            alert.fix(reason: "manifest_deleted", push_id:, pull_request_id:)
          end
        end

        def reason_to_skip_message(payload)
          # We can skip all messages if Dependabot alerts are disabled in GHES.
          unless SecurityProduct::VulnerabilityAlerts.enabled_for_instance?
            return :alerts_disabled
          end

          # Make sure we have a repository ID in the message. Why wouldn't we?
          repository_id = payload[:repository_id]
          unless repository_id > 0
            return :missing_repository_id
          end

          manifest_path = payload[:manifest_path]
          unless manifest_path.present?
            return :missing_manifest_path
          end

          # We save the most expensive checks for last so we can avoid
          # performing unnecessary database queries.
          #
          # Go get the repository. If it's not there, we can skip the message.
          @repository =
            Repositories::Public.find_active(repository_id)
          unless @repository
            return :missing_repository
          end

          # We only update a repository's vulnerability exposure if it has
          # vulnerability alerts enabled.
          unless @repository.vulnerability_alerts_enabled?
            return :alerts_disabled
          end

          # Skip if no alerts are fixable for this manifest path
          @fixable_alerts =
            @repository.repository_vulnerability_alerts.fixable
              .where(vulnerable_manifest_path: payload[:manifest_path])
          unless @fixable_alerts.any?
            return :no_fixable_alerts
          end

          # If we made it here, there's no reason to skip. Process on!
          nil
        end
      end
    end
  end
end
