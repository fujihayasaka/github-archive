# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Windbeam
      class DataSubjectMessageProcessor < SingleMessageProcessor
        # This provides resiliency to transient errors by initially retrying
        # transient errors before briefly pausing the processor when the retries
        # are exhausted. The duration of the pause can be configuerd via the
        # transient_error_pause_duration field on the processor instance
        include TransientErrorResiliency

        PARTICIPANT_NAME = "github"
        DEFAULT_GROUP_ID = "github-#{Rails.env}-windbeam-data_subject_message_processor"
        DEFAULT_SUBSCRIBE_TO = /windbeam\.v0\.DataSubjectMessageSecure\Z/

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
        options[:start_from_beginning] = false

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
        end

        # Processes an individual message from Hydro.
        #
        # This is the main hook that you must implement.
        #
        # For individual message processing (in a subclass of `SingleMessageProcessor`), this method will be called once
        # per consumer invocation. For batch message processing (in a subclass of `BatchedMessageProcessor`), the
        # default implementation of `process_batch` will call this method in a loop, once for each message in the batch
        # to be processed by a single consumer invocation.
        #
        # @param message - An individual GitHub::StreamProcessors::Message, which represents a Hydro event.
        #
        # @returns An arbitrary value that sub-classes may use for internal testing but that is ignored by this base
        #   class and all framework code in production.
        sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
        def process_message(message)
          payload = message.value
          message_id = payload.fetch(:message_id)
          request_id = payload.fetch(:request_id)
          participant_name = payload[:participant_name]
          data_subject = payload[:data_subject] || {}
          user_id = data_subject[:account_id]
          stage = payload[:stage_name]
          received_at = Time.at(message.timestamp).utc

          GitHub.logger.with_named_tags({
            "gh.dsr.participant.name" => participant_name,
            "gh.dsr.message_id" => message_id,
            "gh.dsr.request_id" => request_id,
            "gh.dsr.stage" => stage,
          }) do
            if participant_name != PARTICIPANT_NAME
              GitHub.logger.debug("Not our participant", { "gh.dsr.response" => "IGNORED" })
              return message.skip("not_our_participant")
            end

            unless FeatureFlag.vexi.enabled?(:windbeam_coordinated_user_deletion, default: false)
              GitHub.logger.debug("Feature flag not enabled", { "gh.dsr.response" => "SKIPPED" })
              respond_to_windbeam(
                message_id: message_id,
                request_id: request_id,
                response_type: :SKIPPED,
                received_at: received_at,
              )
              message.success
              return
            end

            process_stage(
              message: message,
              stage: stage,
              user_id: user_id,
              message_id: message_id,
              request_id: request_id,
              received_at: received_at,
            )
          end
        end

        # Use the same status prefix as `UserDeleteJob` to maintain stafftools functionality around user deletes.
        sig { returns(String) }
        def self.prefix
          "user-delete-job"
        end

        sig { params(user_id: Integer).returns(String) }
        def self.job_id(user_id)
          "#{prefix}_#{user_id}"
        end

        sig { params(user_id: Integer).returns(T.nilable(Feeds::JobStatus)) }
        def self.status(user_id)
          Feeds::JobStatus.find(job_id(user_id))
        end

        private

        sig do
          params(
            message: GitHub::StreamProcessors::Message,
            stage: T.untyped,
            user_id: Integer,
            message_id: String,
            request_id: String,
            received_at: Time,
          ).void
        end
        def process_stage(message:, stage:, user_id:, message_id:, request_id:, received_at:)
          case stage
          when :SOFT_DELETE
            GitHub.logger.debug("skipping", { "gh.dsr.response" => "SKIPPED" })
            respond_to_windbeam(
              message_id: message_id,
              request_id: request_id,
              response_type: :SKIPPED,
              received_at: received_at,
            )
            message.success
          when :HARD_DELETE
            user = with_write { User.find_by(id: user_id) }

            if user.nil?
              GitHub.logger.error("unable to find user for request", { "gh.dsr.error" => "user not found", "gh.dsr.response" => "FAILED" })
              respond_to_windbeam(
                message_id: message_id,
                request_id: request_id,
                response_type: :FAILED,
                received_at: received_at,
              )
              message.success
            else
              execute_deletion(user:, message:, message_id:, request_id:, received_at:)
            end
          when :EXPORT
            GitHub.logger.debug("no export stage", { "gh.dsr.response" => "SKIPPED" })
            respond_to_windbeam(
              message_id: message_id,
              request_id: request_id,
              response_type: :SKIPPED,
              received_at: received_at,
            )
            message.success
          when :PURGE
            GitHub.logger.debug("no purge stage", { "gh.dsr.response" => "SKIPPED" })
            respond_to_windbeam(
              message_id: message_id,
              request_id: request_id,
              response_type: :SKIPPED,
              received_at: received_at,
            )
            message.success
          else
            GitHub.logger.warn("Unknown stage", { "gh.dsr.response" => "SKIPPED" })
            respond_to_windbeam(
              message_id: message_id,
              request_id: request_id,
              response_type: :SKIPPED,
              received_at: received_at,
            )
            message.success
          end
        end

        sig do
          params(
            user: User,
            message: GitHub::StreamProcessors::Message,
            message_id: String,
            request_id: String,
            received_at: Time,
          ).void
        end
        def execute_deletion(user:, message:, message_id:, request_id:, received_at:)
          if user.never_deletable?
            GitHub.logger.error("cannot delete this user", { "gh.dsr.error" => "non-deletable user", "gh.dsr.response" => "FAILED" })
            respond_to_windbeam(
              message_id: message_id,
              request_id: request_id,
              response_type: :FAILED,
              received_at: received_at,
            )
            message.success
            return
          end

          status = Feeds::JobStatus.create(id: self.class.job_id(user.id))
          status.track do
            with_write do
              user.remove!
            end
          end

          respond_to_windbeam(
            message_id: message_id,
            request_id: request_id,
            response_type: :COMPLETE,
            received_at: received_at,
          )
          message.success
        rescue StandardError => e
          GitHub.logger.error("unknown error", { "gh.dsr.error" => "failed due to exception", "gh.dsr.response" => "FAILED", "exception.message" => e.message, "exception.type" => e.class.name })
          Failbot.report(e, dsr_request_id: request_id)
          respond_to_windbeam(
            message_id: message_id,
            request_id: request_id,
            response_type: :FAILED,
            received_at: received_at,
          )
          raise
        end

        sig do
          params(
            message_id: String,
            request_id: String,
            response_type: Symbol,
            received_at: Time,
          ).void
        end
        def respond_to_windbeam(message_id:, request_id:, response_type:, received_at:)
          Dsr::WindbeamDeletionResponder.respond(
            message_id: message_id,
            request_id: request_id,
            response_type: response_type,
            received_at: received_at,
          )
        rescue StandardError => e
          GitHub.logger.error("couldn't talk to windbeam", { "gh.dsr.error" => "failed due to exception talking to windbeam" })
          Failbot.report(e, dsr_request_id: request_id)
        end
      end
    end
  end
end
