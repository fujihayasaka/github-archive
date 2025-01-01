# typed: strict
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    class Executor
      extend T::Sig

      sig do
        params(
          processor: ::Licensing::Vss::SubscriptionEventProcessor,
          consumer: GitHub::AzureServiceBus::Consumer,
          shutdown_signals: T::Array[Symbol]
        ).void
      end
      def self.run(processor:, consumer:, shutdown_signals: [:INT])
        new(processor: processor, consumer: consumer, shutdown_signals: shutdown_signals).run
      end

      sig do
        params(
          processor: ::Licensing::Vss::SubscriptionEventProcessor,
          consumer: GitHub::AzureServiceBus::Consumer,
          shutdown_signals: T::Array[Symbol]
        ).void
      end
      def initialize(processor:, consumer:, shutdown_signals: [:INT])
        @processor = processor
        @consumer = consumer
        @shutdown_signals = shutdown_signals
        @processor_loop = T.let(nil, T.nilable(Thread))
        @signal_monitor = T.let(nil, T.nilable(Thread))
        @trapped = T.let(nil, T.nilable(Symbol))
      end

      sig { returns(T.noreturn) }
      def run
        puts "Starting up #{processor.class}"

        setup_signal_handlers

        run_processor_loop do
          wait_for_signals
          puts "Shutting down #{processor.class}"
        end

        exit
      end

      private

      sig { returns(::Licensing::Vss::SubscriptionEventProcessor) }
      attr_reader :processor
      sig { returns(GitHub::AzureServiceBus::Consumer) }
      attr_reader :consumer
      sig { returns(T::Array[Symbol]) }
      attr_reader :shutdown_signals

      sig { params(block: T.nilable(T.proc.void)).void }
      def run_processor_loop(&block)
        @processor_loop = Thread.new { start } # rubocop:disable GitHub/ThreadUse
        @processor_loop.abort_on_exception = true

        yield if block_given?

        shutdown
      end

      sig { void }
      def start
        consumer.each_message do |message|
          processor.process(message)
        end
      end

      sig { void }
      def shutdown
        consumer.close
        T.must(@processor_loop).join
      end

      sig { void }
      def setup_signal_handlers
        puts "Waiting for #{shutdown_signal_names.join(', ')} to shutdown"

        @signal_monitor = Thread.new do # rubocop:disable GitHub/ThreadUse
          this_thread = Thread.current

          shutdown_signals.each do |signal|
            Signal.trap(signal) do
              @trapped = signal
              this_thread.kill
            end
          end

          sleep
        end
        @signal_monitor.abort_on_exception = true
      end

      sig { void }
      def wait_for_signals
        T.must(@signal_monitor).join

        puts "Received SIG#{@trapped}"
      end

      sig { returns(T::Array[String]) }
      def shutdown_signal_names
        shutdown_signals.map { |signal| "SIG#{signal}" }
      end
    end
  end
end
