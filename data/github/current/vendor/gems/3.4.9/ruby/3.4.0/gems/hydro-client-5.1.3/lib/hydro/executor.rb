module Hydro
  class Executor

    # Public: Build a new executor to run a processor as a service.
    #
    # process          - A Hydro::Processor instance.
    # consumer         - A Hydro::Consumer to pull messages from.
    # shutdown_signals - An Array<Symbol> of UNIX signals that should shut down the processor.
    def initialize(processor:, consumer:, shutdown_signals: [:INT])
      @processor = processor
      @consumer = consumer
      @shutdown_signals = shutdown_signals
    end

    # Blocks until the @processor thread exits gracefully (i.e. due to shutdown) or throws an
    # uncaught error
    def run
      puts "Starting up #{processor.class}"

      setup_signal_handlers

      run_processor_loop do
        wait_for_threads
        puts "Shutting down #{processor.class}"
      end
    end

    private

    attr_reader :processor, :consumer, :shutdown_signals

    def run_processor_loop
      # Differentiate between multiple threads running the same processor
      caller_thread_name = Thread.current.name
      @processor_loop = Thread.new do
        Thread.current.name = "#{caller_thread_name}-processor-loop"
        # Avoid emitting the exception multiple times to STDERR; rely on join to handle error
        Thread.current.report_on_exception = false
        start
      end

      yield if block_given?

      shutdown
    end

    def start
      processor.consumer = consumer
      processor.run_callbacks(:open) do
        consumer.open
      end

      if processor.batching?
        consumer.each_batch do |batch|
          processor.process_with_consumer(batch, consumer)
        end
      else
        consumer.each_message do |message|
          processor.process_with_consumer(message, consumer)
        end
      end
    end

    def shutdown
      processor.run_callbacks(:close) do
        consumer.close
      end
      @processor_loop.join if @processor_loop&.alive?
    end

    def setup_signal_handlers
      puts "Waiting for #{shutdown_signal_names.join(', ')} to shutdown"

      @signal_monitor = Thread.new do
        this_thread = Thread.current
        # Report the first time just in case
        this_thread.report_on_exception = true

        shutdown_signals.each do |signal|
          Signal.trap(signal) do
            @trapped = signal
            this_thread.kill
          end
        end

        sleep
      end
    end

    def create_waiter_thread(name, waited_on_thread)
      Thread.new(name, waited_on_thread) do |name, waited_on_thread|
        Thread.current.name = name
        # Avoid emitting the exception multiple times to STDERR; rely on join to handle error
        Thread.current.report_on_exception = false
        begin
          # Joining on the waited_on_thread ensures that uncaught errors are surfaced to callers
          # waiting on the current thread, i.e. the returned waiter thread
          waited_on_thread.join
        ensure
          @queue << waited_on_thread
        end
      end
    end

    def wait_for_threads
      # We don't know which of the signal_monitor or processing loop threads will exit first,
      # so listen for the first one that does
      @queue = Thread::Queue.new

      @signal_monitor_waiter_thread = create_waiter_thread("signal-monitor-waiter", @signal_monitor)
      @processor_loop_waiter_thread = create_waiter_thread("processor-loop-waiter", @processor_loop)

      # We must join on each respective waiter thread to ensure uncaught errors from the
      # processor_loop and signal_monitor threads are re-thrown in the current thread
      case @queue.pop
      when @signal_monitor
        puts "Received SIG#{@trapped}"
        @signal_monitor_waiter_thread.join
        puts "Signal monitor waiter thread finished"
      when @processor_loop
        puts "Processor thread finished"
        @signal_monitor.kill # No need to wait for signals or join on the thread - we're already exiting
        @processor_loop_waiter_thread.join
        puts "Processor waiter thread finished"
      end
    end

    def shutdown_signal_names
      shutdown_signals.map { |signal| "SIG#{signal}" }
    end
  end
end
