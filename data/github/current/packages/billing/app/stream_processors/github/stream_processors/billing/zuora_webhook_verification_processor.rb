# typed: strict
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module Billing
      class ZuoraWebhookVerificationProcessor < SingleMessageProcessor
        include TransientErrorResiliency

        DEFAULT_GROUP_ID_PREFIX = T.let("github-#{Rails.env}-billing-zuora_webhook_verification_processor", String)
        DEFAULT_SUBSCRIBE_TO = /github\.billing\.v0\.ZuoraWebhook\Z/

        # This is the timeout used for determining if a given Kafka consumer has
        # failed or quit due to e.g. a deploy. Setting it to a lower value is NOT
        # recommended if your Hydro processor interacts with the database, since
        # Freno may wait up to 30 seconds when throttling writes. Processors that
        # do not interact with a database may lower this value to allow faster
        # consumer group rebalancing during deploys and processor failures.
        #
        # See https://kafka.apache.org/documentation/#session.timeout.ms
        options[:session_timeout] = 300.seconds

        # This value must be greater than "session_timeout"
        #
        # See https://github.com/zendesk/ruby-kafka#understanding-timeouts
        options[:socket_timeout] = 305.seconds

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
        sig { returns(T::Set[Integer]) }
        def found_webhook_ids
          T.must(@found_webhook_ids)
        end

        sig { returns(T.nilable(Integer)) }
        def min_processed_webhook_id
          @min_processed_webhook_id
        end

        sig { returns(T.nilable(Integer)) }
        def max_processed_webhook_id
          @max_processed_webhook_id
        end

        sig { returns(T.nilable(Integer)) }
        def processed_webhook_count
          @processed_webhook_count
        end

        sig do
          params(
            group_id: T.nilable(String),
            subscribe_to: T.nilable(Regexp),
            pending_webhook_ids: T::Array[Integer]
          ).void
        end
        def setup(group_id: nil, subscribe_to: nil, pending_webhook_ids: [])
          options[:group_id] ||= group_id
          options[:subscribe_to] ||= subscribe_to

          options[:group_id] ||= "#{DEFAULT_GROUP_ID_PREFIX}-#{SecureRandom.hex(6)}"
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          @pending_webhook_ids = T.let(pending_webhook_ids.to_set, T.nilable(T::Set[Integer]))
          @found_webhook_ids = T.let(Set.new, T.nilable(T::Set[Integer]))
          @min_processed_webhook_id = T.let(nil, T.nilable(Integer))
          @max_processed_webhook_id = T.let(nil, T.nilable(Integer))
          @processed_webhook_count = T.let(nil, T.nilable(Integer))

          self.transient_error_max_retries = 10
        end

        sig { override.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
        def process_message(message)
          webhook_id = message.value[:webhook_id]
          return unless webhook_id

          id = webhook_id.to_i

          # Track min/max processed webhook IDs and count
          @min_processed_webhook_id = id if @min_processed_webhook_id.nil? || id < @min_processed_webhook_id
          @max_processed_webhook_id = id if @max_processed_webhook_id.nil? || id > @max_processed_webhook_id
          @processed_webhook_count = (@processed_webhook_count || 0) + 1

          return unless T.must(@pending_webhook_ids).include?(id)
          return if T.must(@found_webhook_ids).include?(id)

          T.must(@found_webhook_ids).add(id)

          GitHub.dogstats.increment("zuora.webhook.verification.found", tags: ["topic:#{message.topic}"])
          GitHub.logger.info("Verified Zuora webhook publish in Hydro", {
            "code.namespace" => self.class.name,
            "code.function" => "process_message",
            "gh.billing.zuora.webhook_id" => id,
            "messaging.destination" => message.topic,
            "messaging.kafka.source.partition" => message.partition,
            "messaging.kafka.message.offset" => message.offset,
            "gh.hydro.message.timestamp" => message.timestamp,
          })
        end

        private

        sig { returns(T::Set[Integer]) }
        def pending_webhook_ids
          T.must(@pending_webhook_ids)
        end
      end
    end
  end
end
