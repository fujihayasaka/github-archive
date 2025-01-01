# typed: true
# frozen_string_literal: true

module ConcurrentFaraday
  module Instrumentation
    class Event
      attr_reader :exception_object, :duration
      def initialize
        @exception_object = nil
        @duration = nil
      end

      def record!
        start!
        ret = nil
        begin
          ret = yield
        rescue Exception => e # rubocop:todo Lint/GenericRescue
          @exception_object = e
          raise e
        ensure
          finish!
        end
        ret
      end

      def start!
        @start = now
      end

      # Finish is called within the `record!` method.
      # The Event is created in the main thread, however,
      # the `record!` method is called in a thread on
      # `ThreadedParallelManager`.
      # Therefore, this method needs to be thread safe.
      # And make sure `finish!` will not alter the state twice.
      #
      # In a case of a earlier timeout, `finish!` will be manually called,
      # also see FutureResponse#wait method for more.
      def finish!(exception_object = nil, duration = nil)
        @duration = duration || (now - @start)
        @exception_object = exception_object if exception_object
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_millisecond)
      end
    end
  end
end
