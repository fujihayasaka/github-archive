# typed: true
# frozen_string_literal: true

require "github/stream_processors/memex_live_updates/strategy"
require "github/stream_processors/memex_live_updates/message"

module GitHub
  module StreamProcessors
    class MemexLiveUpdatesProcessor < SingleMessageProcessor
      DEFAULT_GROUP_ID = "memex_live_updates_processor"

      DEFAULT_SUBSCRIBE_TO = GitHub::StreamProcessors::MemexLiveUpdates::Strategy.registered_topics

      # Stats naming
      STATS_PREFIX = "memex.#{DEFAULT_GROUP_ID}"
      METRIC_SUCCESS_MESSAGE = "#{STATS_PREFIX}.message_success"
      METRIC_ERROR_MESSAGE = "#{STATS_PREFIX}.message_error"
      METRIC_SKIPPED_MESSAGE = "#{STATS_PREFIX}.message_skipped"
      METRIC_PROCESS_TIME = "#{STATS_PREFIX}.process_time"

      exempt_from_tenant_context_requirement

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

      # Public: Process a single Hydro message
      #
      # message - The Hydro message to process
      #
      # Returns nothing
      def process_message(consumer_message)
        message = GitHub::StreamProcessors::MemexLiveUpdates::Message.new(consumer_message)
        strategy = GitHub::StreamProcessors::MemexLiveUpdates::Strategy.for_message(message)

        result = strategy.execute!

        if result.success?
          success(message, result.sockets_updated)
        else
          skip(message, result.error_message)
        end

      rescue => err # rubocop:todo Lint/RescueException
        error(message, err)
      end

      # Log how long it took for a message to process all the way through to
      # success or error and send to stats service with relevant tags.
      #
      # message - Object<HydroConsumerMessage>
      # rows_affected - Integer
      # error - Object<Exception>
      #
      # Returns nothing.
      def instrument_processing_time(message, rows_affected, error = nil)
        start_time = Time.at(message.timestamp)
        result = error ? "error" : "success"
        tags = stats_tags_default(message) << "result:#{result}"
        tags << "fanout:#{fanout_size(rows_affected)}" if rows_affected
        tags << "error:#{error.class.name.demodulize.underscore}" if error
        GitHub.dogstats.timing_since(METRIC_PROCESS_TIME, start_time, tags: tags)
      end

      # Provide standard tags that we want to capture from every message,
      # regardless of the metric.
      #
      # message - Object<HydroConsumerMessage>
      #
      # Returns Array
      def stats_tags_default(message, reason = nil)
        tags = [
          "topic:#{message.topic}",
          "partition:#{message.partition}",
          "replay:#{replaying?}"
        ]

        if reason.present?
          tags << "reason:#{reason}"
        end

        tags
      end

      # Encapsulate the various logging/stats logic that we want to execute
      # anytime a message is skipped. NOTE: Since reason will be converted to tags,
      # its value should always be static in order to prevent cardinality explosions.
      # See https://git.io/J3Ej8 for more.
      #
      # message - Object<HydroConsumerMessage>
      # reason - String
      #
      # Returns nothing (of interest)
      def skip(message, reason)
        message.skip(reason)
        GitHub.dogstats.increment(METRIC_SKIPPED_MESSAGE, tags: stats_tags_default(message, reason))
        log_results("process_message", message, 0)
        message
      end

      # Encapsulate the various logging/stats logic that we want to execute
      # anytime a message is successful. NOTE: Since reason will be converted to tags,
      # its value should always be static in order to prevent cardinality explosions.
      # See https://git.io/J3Ej8 for more.
      #
      # message - Object<HydroConsumerMessage>
      # rows - number
      #
      # Returns nothing (of interest)
      def success(message, rows)
        message.success
        GitHub.dogstats.increment(METRIC_SUCCESS_MESSAGE, tags: stats_tags_default(message))
        log_results("process_message", message, rows)
        message
      end

      # Encapsulate the various logging/stats logic that we want to execute
      # anytime a message is errored. NOTE: Since reason will be converted to tags,
      # its value should always be static in order to prevent cardinality explosions.
      # See https://git.io/J3Ej8 for more.
      #
      # message - Object<HydroConsumerMessage>
      # err - Error
      #
      # Returns nothing (of interest)
      def error(message, err)
        message.error(err)
        GitHub.dogstats.increment(METRIC_ERROR_MESSAGE, tags: stats_tags_default(message))
        log_results("process_message", message, 0, err)
        message
      end

      private def fanout_size(count)
        case
        when count < 5
          "small"
        when count >= 10
          "large"
        else
          "medium"
        end
      end

      def log_results(fn_name, message, rows_affected, error = nil)
        begin
          instrument_processing_time(message, rows_affected, error)
        ensure
          log_hash = {
            "code.namespace": "MemexLiveUpdatesProcessor",
            "code.function": fn_name,
            "gh.actor.id": message.actor_id,
            "gh.hydro.msg.topic": message.topic,
            "gh.memex.content.id": message.content_id,
            "gh.memex.content.type": message.content_type,
            "gh.memex.project.id": message.memex_project_id,
            "gh.hydro.consumer.replay": replaying?
          }
          if error
            Failbot.report(error, **log_hash)
            GitHub.logger.error(error, **log_hash)
          else
            GitHub.logger.info(
              "#{log_hash["code.function"]} successfully processed #{rows_affected} items",
              **log_hash
            )
          end
        end
      end
    end
  end
end
