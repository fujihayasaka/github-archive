# frozen_string_literal: true
#              


require "vexi/instrumenter"

module Vexi
  class InstrumentationContext
    def initialize(store = {})
      @store =      (store                                   )
      @children =      ({}                                         )
    end

    def instrument_timing(operation, properties: {}, &_block)
      @store[operation] = properties
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield(properties)
    ensure
      time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      # It's possible that any of the lines above will be interrupted by a timeout error
      # To avoid raising exceptions in the consumer of these events, we should ensure
      # that the result of finish_time - start_time is exactly 0 so it can be filtered out
      start_time ||= time
      finish_time = time

      properties[:measured_start] = start_time
      properties[:measured_finish] = finish_time

      # Ensure that the store was set in case the first assignment failed due to a timeout error
      @store[operation] = properties unless @store.has_key?(operation)
    end

    def instrument_error(name, error, message:, properties: {})
      self[name] = properties.merge!({
        error: error,
        message: message,
      })
    end

    def [](key)
      @store[key]
    end

    def []=(key, value)
      @store[key] = value
    end

    def to_h
      @store
    end
  end
end
