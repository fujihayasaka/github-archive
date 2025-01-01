# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    class PullRequestMergeCommitRequestedProcessor < BaseProcessor
      extend T::Sig

      DEFAULT_GROUP_ID = "github-#{Rails.env}-pull_request_merge_commit_requested_processor"
      DEFAULT_SUBSCRIBE_TO = /github\.pull_requests\.v1\.MergeCommitRequested\Z/

      include TransientErrorResiliency

      default_to_write_connection!

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

      # Enable batching with a feature flag.
      def batching?
        GitHub.flipper[:stream_processor_batching_batchable_cprmc_jobs].enabled?
      end

      # Non-Batching Mode
      def process_message(message)
        repository_id = message.value[:repository_id]
        pull_request_id = message.value[:pull_request_id]
        message_timestamp = Time.at(message.timestamp)

        PullRequests::MergeCommit.request!(repository_id:, pull_request_id:)

        GitHub.dogstats.distribution(
          "pull_requests.merge_commits.stream_processor.time_to_enqueue",
          ((Time.now - message_timestamp).to_f * 1000),
          tags: ["batched:false"]
        )
      end

      # Batching Mode
      def process_batch(batch)
        # wrap incoming batch in the event that this is inadvertently a single message
        batch = Array.wrap(batch)

        # Required for telemetry.
        @current_batch = batch

        # This overrides the super version of process_batch(*) and pulls in existing behavior.
        run_callbacks :batch do
          time("process_batch") do
            records = T.let(Set.new, T::Set[[Integer, Integer, Time]])

            batch.each do |message|
              record = message.value.values_at(:repository_id, :pull_request_id).map(&:to_i)

              # Skip over malformed requests.
              next if record.any?(&:zero?)

              record << Time.at(message.timestamp)
              records << record
            end

            PullRequests::MergeCommit.batch_request_with_block(records.to_a) do
              safe_trigger_heartbeat
            end

            # Move the kafka cursor to the most recently processed. Borrowed from:
            # https://github.com/github/github/blob/cea7c88829123b1605e71cc4a2f637f1f63ee622/lib/github/stream_processors/stratocaster_timeline_updates_processor.rb#L72
            consumer.mark_message_as_processed(batch.last)
          end
        end
      end
    end
  end
end
