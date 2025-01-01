# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    # Mix-in provides Dogstats instrumentation
    # See `GitHub::StreamProcessors::BaseProcessor`
    module Instrumentation
      # Internal: Instruments the size of a batch of messages processed
      #
      # Returns nothing
      def instrument_batch_size(size)
        stats.count("github.stream_processor.batch_size", size, tags: default_stats_tags)

        if metric_prefix
          stats.count("#{metric_prefix}.batch_size", size)
        end
      end

      # Internal: Increments a counter for messages that failed to process
      #
      # exception - An optional Exception that caused the message failure,
      #             which is included as a Dogstats tag via its class name
      #
      # Returns nothing
      def instrument_message_failed(exception)
        error = exception && exception.class.name.underscore
        stats.increment("github.stream_processor.message_failed", tags: default_stats_tags + ["error:#{error}"])

        if metric_prefix
          stats.increment("#{metric_prefix}.failed_message")
        end
      end

      # Internal: Increments a counter for messages received and records the latency
      # between when the message was created and when it was received
      #
      # latency_ms - The latency between when the message was created and when it
      #              was received in milliseconds
      #
      # Returns nothing
      def instrument_message_received(latency_ms)
        stats.increment("github.stream_processor.message_received", tags: default_stats_tags)
        stats.timing("github.stream_processor.message_latency", latency_ms.to_i, tags: default_stats_tags)

        if metric_prefix
          stats.increment("#{metric_prefix}.message_received")
          stats.timing("#{metric_prefix}.latency", latency_ms.to_i)
        end
      end

      # Internal: Increments a counter for messages that were skipped
      #
      # reason - The reason that the message was skipped, which is included as a
      #          Dogstats tag
      #
      # Returns nothing
      def instrument_message_skipped(reason)
        stats.increment("github.stream_processor.message_skipped", tags: default_stats_tags + ["reason:#{reason}"])

        if metric_prefix
          stats.increment("#{metric_prefix}.message_skipped", tags: ["reason:#{reason}"])
        end
      end

      # Internal: Increments a counter for messages processed successfully
      #
      # Returns nothing
      def instrument_message_successful
        stats.increment("github.stream_processor.message_successful", tags: default_stats_tags)

        if metric_prefix
          stats.increment("#{metric_prefix}.message_processed")
        end
      end

      # Internal: Instruments the amount of time since the last heartbeat was sent
      #
      # time_since_heartbeat_ms - The amount of time since the last heartbeat was
      #                           sent in milliseconds
      #
      # Returns nothing
      def instrument_time_since_heartbeat(time_since_heartbeat_ms)
        stats.timing("github.stream_processor.time_since_heartbeat", time_since_heartbeat_ms.to_i, tags: default_stats_tags)
      end

      # Internal: Records timing for an arbitrary block of code
      #
      # label - The label to use for the timing metric
      #
      # Returns nothing
      def time(label, tags: [], &block)
        if metric_prefix
          stats.time("#{metric_prefix}.#{label}") do
            stats.time("github.stream_processor.#{label}", tags: default_stats_tags + tags, &block)
          end
        else
          stats.time("github.stream_processor.#{label}", tags: default_stats_tags + tags, &block)
        end
      end

      # Internal: The default Dogstats tags to use for metrics
      #
      # These tags are used for metrics in the common naming scheme but NOT for
      # metrics generated with a custom metric prefix.
      #
      # Returns Array
      def default_stats_tags
        [
          "processor:#{self.class.name.underscore}",
          "service:#{logical_service}",
          "replay:#{!!execution_context&.fetch("replay", false)}",
          "group_id:#{group_id}",
        ]
      end
    end
  end
end
