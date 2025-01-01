# typed: true
# frozen_string_literal: true

module ConcurrentFaraday
  class Promise < ::Promise
    extend T::Generic

    Value = type_member

    def initialize(future = nil)
      @future = future
      @timeout = nil
      super()
    end

    def with_timeout(seconds)
      @timeout = seconds
      self
    end

    attr_reader :instrument_event

    def wait
      return super if @future.nil?

      result = @future.result(@timeout)
      if result.nil?
        # time-out
        err = Faraday::TimeoutError.new("Concurrent::Promises::Future timeout while waiting for a result.")
        # When we go over the timeout, we force the instrumenter to finish the request too
        # so we will have instrumentation details.
        @instrument_event = ConcurrentFaraday::Instrumentation::Event.new
        @instrument_event.finish!(err, @timeout)

        reject(err)
        return
      end
      fulfilled, value, reason_e = *result
      if fulfilled
        r, event = *value
        @instrument_event = event
        fulfill(r)
      else
        @instrument_event = reason_e.event
        reject(reason_e.wrapped_err)
      end
    end
  end
end
