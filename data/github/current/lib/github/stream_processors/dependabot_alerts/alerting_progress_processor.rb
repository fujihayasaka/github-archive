# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module DependabotAlerts
      class AlertingProgressProcessor < BaseProcessor
        include TransientErrorResiliency
        exempt_from_tenant_context_requirement

        DEFAULT_GROUP_ID = "github-#{Rails.env}-dependabot_alerts-alerting_progress_processor"
        DEFAULT_SUBSCRIBE_TO = /github\.progress\.v0\.ProgressStop\Z/
        DEAD_LETTER_TOPIC = "dependabot.v0.AlertingProgressStop.DeadLetter"

        # Examples:
        # - vulnerable-version-range-alerting-process.123
        # - vulnerability-alerting-event.456
        KEY_PATTERN = %r{
          \A
            (?<model>
              vulnerable-version-range-alerting-process # Advisory alerting
              |                                         # or
              vulnerability-alerting-event              # repository alerting
            )
            \.
            (?<id>\d+) # ID of the model specified above
          \z
        }x

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

        # Clear any instance variable that hold message-specific information.
        # That way, we can collect metrics using these instance variables
        # without worrying that they leak between messages.
        set_callback :message, :before, :clear_state_before_message

        # Public: Configure the Hydro processor
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.transient_error_max_retries = 10
          self.dead_letter_topic = DEAD_LETTER_TOPIC
        end

        # Public: Find either the VulnerableVersionRangeAlertingProcess or
        # VulnerabilityAlertingEvent (based on the key, see KEY_PATTERN),
        # and mark it as processed, now that the corresponding progress is
        # complete.
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        def process_message(message)
          if reason = reason_to_skip_message(message)
            message.skip(reason)
            return
          end

          # Mark @processable as processed. Here, @processable is either a
          # VulnerableVersionRangeAlertingProcess (for advisory alerting on a
          # specific VulnerableVersionRange) or VulnerabilityAlertingEvent (for
          # repository alerting).
          @processable.processed!
        end

        private

        def clear_state_before_message
          @processable = nil
          @message_stats_tags = []
        end

        def reason_to_skip_message(message)
          payload = message.value

          @message_stats_tags << "status:#{payload[:status].downcase}"

          # Every event is expected to be STOP on the ProgressStop topic.
          unless payload[:event] == :STOP
            return :event_not_stop
          end

          # The happy path is COMPLETED progress. Progress could also be
          # STALLED or explicitly STOPPED.
          unless complete?(payload)
            return :incomplete
          end

          key_match = KEY_PATTERN.match(payload[:key])
          unless key_match
            return :unrecognized_key
          end

          # It's tempting to use String#classify and String#constantize here
          # but we don't need to risk loading an unknown constant into memory.
          processable_class =
            case key_match[:model]
            when "vulnerable-version-range-alerting-process"
              VulnerableVersionRangeAlertingProcess
            when "vulnerability-alerting-event"
              VulnerabilityAlertingEvent
            else
              # This reason should only be returned
              # if something is wrong with KEY_PATTERN.
              return :unknown_processable_class
            end

          @message_stats_tags << "processable_class:#{processable_class.name&.underscore}"
          @processable = processable_class.find_by(id: key_match[:id].to_i)

          unless @processable
            return :missing_processable
          end

          # At this point, we know we found a @processable and it is either a
          # VulnerableVersionRangeAlertingProcess or VulnerabilityAlertingEvent
          # so we can safely add its datadog tags to our message-specific tags.
          @message_stats_tags.concat(@processable.datadog_tags)

          if @processable.processed?
            return :already_processed
          end

          nil
        end

        def complete?(payload)
          return true if payload[:status] == :COMPLETED
          return false unless payload[:denominator_locked]
          return true if payload[:denominator] == 0

          # At least 99.9% of available work must be complete.
          1_000 * payload[:numerator] / payload[:denominator] >= 999
        end

        def default_stats_tags
          super + @message_stats_tags.to_a
        end
      end
    end
  end
end
