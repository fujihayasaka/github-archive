# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module UserMetadata
      class UserMetadataBaseProcessor < BaseProcessor
        include TransientErrorResiliency

        RECALCULATION_TOPIC_PATTERN = /github\.user_metadata\.v1\.Recalculation\Z/
        RECALCULATION_SKIP_MESSAGE = "recalculation triggered for another metadata processor"

        options[:min_bytes] = 1.kilobyte
        options[:max_wait_time] = 1.second
        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds
        options[:start_from_beginning] = false
        options[:max_bytes_per_partition] = 100.kilobytes

        def name
          self.class::HYDRO_TARGET_PROCESSOR_NAME
        end

        def process_message(message)
          event = Events::UserMetadataEvent.from(message, self)

          if event.skip?
            GitHub.logger.info(
              "gh.processor.name" => name,
              "messaging.kafka.source.name" => message.topic,
              "messaging.kafka.source.partition" => message.partition,
              "messaging.kafka.message.offset" => message.offset,
              "gh.user_metadata.event.skip" => true,
              "gh.user_metadata.event.skip_reason" => event.skip_reason,
              "gh.user_metadata.event.name" => event.name,
            )
            return message.skip(event.skip_reason)
          end

          # If the processor is sensitive to replication lag, wait for it to catch up.
          replication_wait = wait_for_replication!(message)

          GitHub.logger.with_named_tags(
            "gh.processor.name" => name,
            "messaging.kafka.source.name" => message.topic,
            "messaging.kafka.source.partition" => message.partition,
            "messaging.kafka.message.offset" => message.offset,
            "gh.user_metadata.event.skip" => false,
            "gh.processor.replication_wait" => replication_wait,
            "gh.user_metadata.event.name" => event.name,
          ) do
            Failbot.push(
              stream_processor: self.class.name.underscore,
              group_id: group_id,
              message_schema: message.schema,
            ) do
              event.users.each do |user|
                previous_context = GH.context.identity_context
                GH.context.identity_context = GH::Auth::IdentityContext::ValueContext.new(user)

                if user.spammy?
                  GitHub.dogstats.increment("#{metric_prefix}.spammy_user")
                  next if GitHub.flipper[:skip_user_metadata_updates_for_spammers].enabled?
                end

                ::UserMetadata.throttle_with_retry(max_retry_count: 5) do
                  # Each retry will wait up to 30 seconds, and our max_session_timeout is 60 seconds. We need to send
                  # a heartbeat on each retry to make sure we don't time out if the first retry attempt fails.
                  safe_trigger_heartbeat
                  ::UserMetadata.retry_on_find_or_create_error do
                    updates = with_read { metadata_updates(event, user) }
                    affected_rows = with_write { update_user_metadata(user, updates) }
                    GitHub.logger.info(
                      "code.namespace" => "StreamProcessors::UserMetadata::UserMetadataBaseProcessor",
                      "code.function" => "update",
                      "gh.user.id" => user.id,
                      "gh.user_metadata.updates" => updates.keys.join(","),
                      "gh.user_metadata.affected_rows" => affected_rows,
                    )
                  end
                end
              ensure
                GH.context.identity_context = previous_context
              end
            end
          end
        end

        # Public: User metadata that this stream processor should update for a given user.
        #
        # event - the UserMetadataEvent currently being processed
        # user  - a User with metadata affected by the event being processed
        #
        # Returns a Hash of metadata key/value pairs to update for the specified user.
        def metadata_updates(event, user)
          raise NotImplementedError
        end

        private

        # If a processor subclass is sensitive to replication lag, it can
        # override this method to wait for it to catch up.
        def wait_for_replication!(message)
          0
        end

        # WaitForReplication expects a specific Timestamp format. This first
        # converts Rational to time, and then passes it into
        # the method that converts it into the format WaitForReplication is
        # expecting.
        #
        # timestamp - Rational - The consumer message.timestamp
        #
        # Returns Time
        def format_time_for_replication(timestamp)
          Timestamp.from_time(Time.at(timestamp))
        end

        # Insert or update the ::UserMetadata object for the given user
        #
        # user     - User which owns this metadata
        # metadata - Hash of metadata attribute => value
        #
        # Returns nothing
        def update_user_metadata(user, metadata)
          metadata_names   = metadata.keys.join(", ")
          metadata_values  = metadata.keys.map { |key| ":#{key}" }.join(", ")
          metadata_updates = metadata.keys.map { |key| "#{key} = VALUES(#{key})" }.join(", ")
          metadata_binds   = metadata.merge(user_id: user.id, now: Time.now.utc)

          sql = Arel.sql(<<-SQL, **metadata_binds)
            INSERT INTO user_metadata
              (user_id, created_at, updated_at, #{metadata_names})
            VALUES (:user_id, :now, :now, #{metadata_values})
            ON DUPLICATE KEY UPDATE
              updated_at = :now,
              #{metadata_updates}
          SQL

          affected_rows = ::UserMetadata.connection.update(sql)
          affected_rows
        end

        # Simple wrapper for connecting to read pool for read operations only.
        def with_read
          ActiveRecord::Base.connected_to(role: :reading) do
            yield
          end
        end

        # Simple wrapper for connecting to write for write operations only.
        def with_write
          ActiveRecord::Base.connected_to(role: :writing) do
            yield
          end
        end
      end
    end
  end
end
