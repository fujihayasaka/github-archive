# typed: true
# frozen_string_literal: true

module ConcurrentFaraday
  class ThreadedParallelManager

    def initialize(num_threads = 1)
      @promises = []
      @thread_pool = Concurrent::FixedThreadPool.new(num_threads)
    end

    def dispatch(*args, &block)
      future = Concurrent::Promises.future_on(@thread_pool, args, block, &TASK)
      ConcurrentFaraday::Promise.new(future)
    end

    def run
      promises, @promises = @promises, []
      promises.each &:sync
    end

    def clear!
      @promises = []
    end

    def queue(promise)
      @promises << promise
    end

    class WrappedError < StandardError
      attr_accessor :event, :wrapped_err
    end

    # This is the task that will be executed in the thread pool.
    # It should create a value which is a excon response and a instrumentation event
    # If it raises and error, it wraps it in a WrappedError in order to also hold
    # a reference the instrumentation event, as that will be used in the case of an error too
    # Note: the Instrumentation event is created here, so other threads won't mutate it.
    def self.task(args, block)
      instrumenter = ConcurrentFaraday::Instrumentation::Event.new
      r = instrumenter.record! { block.call(*args) }
      [r, instrumenter]
    rescue => e # rubocop:todo Lint/GenericRescue
      err = WrappedError.new
      err.wrapped_err = e
      err.event = instrumenter
      raise err
    end

    # Preallocate the worker proc to minimize closure capture risk
    TASK = method(:task)

    private_class_method :task
    private_constant :TASK
  end
end
