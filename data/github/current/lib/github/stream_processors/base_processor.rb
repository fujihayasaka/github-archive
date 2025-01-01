# typed: false
# frozen_string_literal: true

module GitHub
  module StreamProcessors

    class ProcessorPausedError < StandardError; end

    # BaseProcessor provides both an abstract interface and base behaviors for Hydro stream processors in the same way
    # that ApplicationJob provides a base for background jobs.
    #
    # In order to implement a concrete stream processor, you should NOT subclass this base directly. Rather, you
    # should take one of the following paths:
    #
    #   - To process messages individually (i.e. one message per consumer invocation), you should subclass
    #     `SingleMessageProcessor` and implement `process_message`. This is the recommended path for most processors.
    #
    #   - To process messages in batches (i.e. several messages per consumer invocation), you should subclass
    #     `BatchedMessageProcessor`. You then have two further options:
    #
    #     - For simple batching use-cases, you can just implement `process_message` and allow the framework to call it
    #       for you multiple times within a single consumption loop.
    #     - For finer-grained control over batching, you should override `process_batch` (and implement
    #       `process_message` as a no-op).
    #
    # In either case, you can implement any of the following optional hooks for further customization:
    #
    #    - `setup`
    #    - `error_context`
    #    - `error_context_for_message`
    #    - `publish_dead_letter_message`
    #
    # All processors inherit the following behaviors from this base class:
    #
    #   - Service mapping
    #   - Exception handling
    #   - Dogstatsd metrics
    #   - Dead-letter routing
    #   - Pause/Resume message processing
    #
    class BaseProcessor < Hydro::Processor
      extend T::Helpers
      include ActiveSupport::Rescuable
      include GitHub::ServiceMapping
      include GitHub::StreamProcessors::Instrumentation
      # Processor readiness needs to be included before ProcessorPausing
      # to ensure we can start the container even when paused
      include GitHub::StreamProcessors::ProcessorReadiness
      include GitHub::StreamProcessors::ProcessorPausing
      include GitHub::StreamProcessors::CircuitBreaking

      abstract!

      class_attribute :default_to_write_connection, default: false
      class_attribute :errors_to_bubble_to_batch_level
      self.errors_to_bubble_to_batch_level = {
        ::GitHub::StreamProcessors::ProcessorPausedError => proc { true },
      }.freeze

      # Public: The Hydro topic to use, if any, for publishing dead letter messages
      attr_reader :dead_letter_topic

      def self.default_to_write_connection!
        self.default_to_write_connection = true
      end

      define_callbacks :batch, :message

      set_callback :batch, :around, :batch_instrumentation
      set_callback :batch, :before, :safe_trigger_heartbeat
      set_callback :batch, :after, :reset_error_context

      set_callback :message, :before, :push_service_mapping_context
      set_callback :message, :around, :with_remote_call_source_datadog_tags
      set_callback :message, :around, :error_handling
      set_callback :message, :around, :mysql_instrumentation
      set_callback :message, :around, :mysql_database_selection
      set_callback :message, :around, :with_enabled_context

      # We need to include this module here so that the `set_callback`s in `GitHub::StreamProcessors::TenantContext` are called in the right order
      include GitHub::StreamProcessors::TenantContext

      rescue_from StandardError, with: :report_error

      # Register some identifying information
      set_callback :open, :before do
        GitHub.component = :stream_processor
        GitHub.context.push(from: self.class.name)
        push_service_mapping_context
      end

      # Public: Initialize the stream processor
      #
      # The default initializer will set the Hydro options group_id and
      # subscribe_to if they are provided. It will also call the `#setup`
      # method to allow sub-classes to do additional configuration.
      #
      # Sub-classes can change the group_id and subscribe_to Hydro
      # options in `#setup` if needed. This is especially useful when
      # default values are provided by the sub-class.
      #
      # This method accepts arbitrary keyword arguments and forwards them to
      # the `#setup` method along with group_id and subscribe_to.
      #
      # group_id     - The Hydro consumer group that the processor belongs to
      # subscribe_to - A regular expression describing which Hydro topics the
      #                processor consumers
      def initialize(group_id: nil, subscribe_to: nil, rescue_from_standard_error: Rails.env.production?, **kwargs)
        options[:group_id] = group_id
        options[:subscribe_to] = subscribe_to

        @stats = GitHub.dogstats
        @rescue_from_standard_error = rescue_from_standard_error

        # Placeholder for any context callers want to pass along, which can
        # then be used as needed inside process_message implementations.
        @execution_context = {}

        setup(group_id: group_id, subscribe_to: subscribe_to, **kwargs)
      end

      # Public: Additional context about how the processor is being executed
      # -- via a Dead Letter CLI replay, for example.
      attr_accessor :execution_context

      # Processes a message or batch of messages from Hydro, depending on whether the
      # processor overrides the `batching?` method to return `true` or `false`. For any processor
      # that does not strictly require batching, it is highly recommended to override `batching?`
      # to return `false`.
      #
      # IMPORTANT: This method SHOULD NOT be overridden by sub-classes
      #
      # This method consumes messages from Hydro and calls `#process_message` for each message.
      # `#process_message` can provide feedback -- mostly for instrumentation in Dogstatsd -- about
      # the result of processing a given message.
      #
      # Examples:
      #
      #   def process_message(message)
      #     # If a message was skipped for some reason:
      #     return message.skip("reason_for_skip")
      #
      #     # If a message caused an error
      #     return message.error(RuntimeError.new)
      #
      #     # If a message was successful (messages are assumed successful by
      #     # default so this isn't necessary; but it can be done if desired)
      #     return message.success
      #   end
      #
      # If `#process_message` raises an error, the message will automatically be
      # marked with the error that was rescued.
      #
      # batch_or_message - A Hydro::Source::Message or enumeration of Hydro::Source::Messages
      # consumer         - The Hydro::Consumer which is consuming messages
      #
      # Returns nothing
      def process_with_consumer(batch_or_message, consumer)
        if circuit_breaker_pause_processing?
          pause(expires: circuit_breaker_pause_duration, reason: "circuit breaker") unless paused?
        end

        raise ::GitHub::StreamProcessors::ProcessorPausedError if paused?

        reset_error_context

        @consumer = consumer

        if batching?
          process_batch(batch_or_message)
        else
          process_consumer_message(batch_or_message)
        end
      rescue ::GitHub::StreamProcessors::ProcessorPausedError => e
        # This will cause the consumer to exit so all hydro consumer state is cleared.
        # When it's automatically restarted by moda, it will wait until the processor
        # is resumed to start consuming messages again.
        raise e
      rescue => e # rubocop:todo Lint/RescueException
        rescue_with_handler(e) || raise
      end

      protected

      # Protected: The Hydro topic to use, if any, for publishing dead letter messages
      attr_writer :dead_letter_topic

      # Protected: The custom metric prefix to use, if any, for Dogstatsd metrics
      attr_accessor :metric_prefix

      # Protected: The context for errors sent to Failbot, which includes message-specific context
      attr_reader :current_error_context

      # Protected: The Dogstatsd instance to use for recording stats
      attr_reader :stats

      # Protected: Run processor-specific initialization
      #
      # This method is called by `#initialize`. All of the keyword arguments
      # provided to `#initialize` are forwarded to this method, including
      # group_id and subscribe_to.
      #
      # Sub-classes are not required to implement this method.
      #
      # Returns nothing
      def setup(**kwargs)
        # Implementation optional
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
      sig { abstract.params(message: GitHub::StreamProcessors::Message).returns(T.anything) }
      def process_message(message); end

      # Protected: A Hash of non-message-specific context to be included when
      # exceptions are sent to Failbot
      #
      # For message-specific context, use `#error_context_for_message`.
      #
      # Sub-classes are not required to implement this method.
      #
      # Returns Hash
      def error_context
        {}
      end

      # Protected: A Hash of message-specific context to be included when
      # exceptions are sent to Failbot
      #
      # For context that isn't message specific, use `#error_context`.
      #
      # Sub-classes are not required to implement this method.
      #
      # message - The specific Hydro::Source::Message being processed
      #
      # Returns Hash
      def error_context_for_message(message)
        {
          "hydro_msg_topic" => message.topic,
          "hydro_msg_partition" => message.partition,
          "hydro_msg_offset" => message.offset,
        }
      end

      # Protected: Publish a dead letter message when an error is encountered if
      # a dead letter topic is configured
      #
      # This will publish a `github.v1.DeadLetter` message to the configured
      # topic. Sub-classes may override this method if needed to publish a
      # different message schema.
      #
      # message - The Hydro::Source::Message that could not be processed
      # error   - The error that was raised
      #
      # Returns nothing
      def publish_dead_letter_message(message, error)
        return unless dead_letter_topic

        payload = {
          envelope: message.envelope,
          payload: JSON.dump(message.value),
          retries: message.retries + 1,
          error_class: error.class.name,
          error_message: error.message,
          error_backtrace: JSON.dump(error.backtrace.first(100)),
        }

        Hydro::PublishRetrier.publish(
          payload,
          schema: "github.v1.DeadLetter",
          topic: dead_letter_topic,
        )
      end

      # Protected: Triggers a Kafka consumer heartbeat, which lets Kafka know
      # that the consumer is still alive and processing.
      #
      # Triggering a heartbeat _can_ raise exceptions, for example if Kafka is
      # rebalancing the consumer group. This method swallows such exceptions as
      # they do not need to derail processing of messages.
      #
      # This method is automatically invoked for every message. Sub-classes may
      # wish to invoke this method if doing some processing that could cause a
      # heartbeat timeout.
      #
      # Returns nothing
      def safe_trigger_heartbeat
        if defined?(@last_heartbeat_at)
          time_since_heartbeat_ms = (Time.now.to_f - @last_heartbeat_at.to_f) * 1_000
          instrument_time_since_heartbeat(time_since_heartbeat_ms)
        end
        @last_heartbeat_at = Time.now

        consumer&.trigger_heartbeat
      rescue Hydro::Source::Error, Kafka::RebalanceInProgress, Kafka::HeartbeatError
        # Pass
      end

      # Backoff Scale
      BACKOFF_RETRIES = [0, 0.5, 1.5, 3.5, 5, 35, 60, 115]

      # Protected: Use a backoff scale to sleep depending
      # on the retries count from the message.
      #
      # It will only attempt to sleep if processing a DeadLetter typed message.
      #
      # It will use the retries to sleep and return true, so the caller(processor)
      # can continue the process. It will return false if the caller should
      # not continue it.
      # It is up to the caller to decide if continue or not, however
      # it is advised to use the return boolean state to halt and skip the message.
      #
      #
      # Returns boolean
      def backoff_process_and_continue?(message, backoff_scale: BACKOFF_RETRIES)
        return true unless message.dead_letter_message?

        retries = message.retries || 0
        sleep_secs = backoff_scale[retries]

        GitHub.logger.info(
          "code.namespace" => self.class.name,
          "code.function" => "#backoff_process_and_continue?",
          "messaging.source.name" => message.topic,
          "messaging.kafka.source.partition" => message.partition,
          "messaging.kafka.message.offset" => message.offset,
          "gh.hydro_processor.dead_letter_retrying.sleep_secs" => sleep_secs,
          "gh.hydro_processor.dead_letter_retrying.retries" => retries,
          "gh.hydro_processor.dead_letter_retrying.original_error_class" => message.original_error_class,
        )
        unless sleep_secs
          # If it got to the limit of the backoff scale, move on
          return false
        end
        sleep sleep_secs
        safe_trigger_heartbeat
        true
      end

      private

      attr_reader :current_batch, :current_message

      def process_consumer_message(consumer_message)
        message = Message.build(consumer_message, dead_letter_topic: dead_letter_topic)
        @current_message = message

        # Tombstone messages currently don't have a timestamp and would therefore report incorrect values
        if message.timestamp.present?
          latency_ms = (Time.now.to_f - message.timestamp.to_f) * 1_000
          instrument_message_received(latency_ms)
        end

        @current_error_context.merge!(error_context_for_message(message))

        GitHub.tracer.in_span("#{self.class.name}#process_message", kind: :internal, attributes: { "code.namespace" => self.class.name }) do |_span|
          time("process_message", tags: ["topic:#{message.topic}", "partition:#{message.partition}"]) do
            Rails.application.executor.wrap do
              run_callbacks :message do
                process_message(message)
              end
            end
          end
        end

        if message.success?
          instrument_message_successful
          circuit_breaker_record_success
          log("Successfully processed Hydro message: #{message.topic}")
        elsif message.skipped?
          instrument_message_skipped(message.cause)
          log("Skipped processing Hydro message - #{message.cause}")
        elsif message.error?
          instrument_message_failed(message.cause)
          circuit_breaker_record_failure
          publish_dead_letter_message(message, message.cause)
          log("Error processing Hydro message - #{message.cause}")
        end

        message
      end

      # Whether or not this processor will process messages in a batch or individually.
      sig { abstract.returns(T::Boolean) }
      def batching?; end

      # Process a batch of messages.
      #
      # @param batch - A group of Hydro events to be processed all at once.
      #
      # @returns An arbitrary value that sub-classes may use for internal testing but that is ignored by this base
      #   class and all framework code in production.
      sig { abstract.params(batch: T::Array[Hydro::Consumer::ConsumerMessage]).returns(T.anything) }
      def process_batch(batch); end

      # Internal: Report an error to Failbot
      #
      # error - The error that was raised
      #
      # Returns nothing
      def report_error(error)
        raise error unless @rescue_from_standard_error

        context = current_error_context || {}
        context = context.merge(
          "processor" => self.class.name,
          "catalog_service" => logical_service,
          "critical" => true
        )

        if GitHub.multi_tenant_enterprise? && FeatureFlag.vexi.enabled_or_raise?(:tenant_context_telemetry_stream_processors_failbot) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
          context = context.merge(GitHub::CurrentTenant.logging_context)
        end

        Failbot.report(error, context)
      end

      # Internal: Resets the error context between messages
      #
      # Returns nothing
      def reset_error_context
        @current_error_context = error_context.deep_dup.merge(execution_context)
      end

      # Private: Abstraction over our replay flag implementation that
      # processors can use to determine if the current invocation was triggered
      # by consumption or manual replay
      #
      # Returns Boolean
      def replaying?
        !!execution_context&.fetch("replay", false)
      end

      def log(statement)
        return unless Rails.env.development?

        puts("[#{self.class.name}] #{statement}")
      end

      def batch_instrumentation
        time("process_with_consumer") do
          instrument_batch_size(current_batch.size)

          yield
        end
      end

      def error_handling
        yield
      rescue Exception => e # rubocop:disable Lint/RescueException
        current_message.error(e)
        if errors_to_bubble_to_batch_level.any? { |error_class, proc| e.is_a?(error_class) && proc.call(e) }
          raise
        else
          rescue_with_handler(e) || raise
        end
      end

      def mysql_instrumentation
        GitHub::MysqlInstrumenter.reset_stats

        GitHub::MysqlInstrumenter.with_track do
          yield

          GitHub::MysqlInstrumenter.queries_per_type_database.each do |host, counts|
            counts ||= {}
            tags_with_host = default_stats_tags + ["rpc_host:#{host}"]

            GitHub.dogstats.count("stream_processor.rpc.mysql.count.reads", counts[:read].to_i, tags: tags_with_host)
            GitHub.dogstats.count("stream_processor.rpc.mysql.count.writes", counts[:write].to_i, tags: tags_with_host)
          end
        end
      end

      def with_remote_call_source_datadog_tags
        class_name = self.class.name&.underscore
        GitHub.context.push(remote_call_source_datadog_tags: [
          "source_type:stream_processor",
          "stream_processor:#{class_name}",
          "source:stream_processor-#{class_name}",
        ])

        yield
      ensure
        GitHub.context.pop_key(:remote_call_source_datadog_tags)
      end

      def mysql_database_selection
        last_operations = DatabaseSelector::LastOperations.from_hydro_message(current_message)

        ::DatabaseSelector.instance.track_writes(last_operations) do
          if default_to_write_connection?
            yield
          else
            with_read do
              yield
            end
          end
        end
      end

      def default_to_write_connection?
        self.class.default_to_write_connection
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

      # Ensure message processing has a fresh context
      def with_enabled_context
        GH::Context.enabled { yield }
      end

      # Connect to write for specific clusters only
      def with_primaries(*primaries, &block)
        if ActiveRecord::Base.single_database_cluster?
          return with_write(&block)
        end

        ActiveRecord::Base.connected_to_many(primaries, role: :writing, &block)
      end
    end
  end
end
