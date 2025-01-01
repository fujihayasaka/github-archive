# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"
require "vexi/instrumenter"

module Vexi
  class InstrumentationContext
    def initialize(store = {})
      @store = T.let(store, Instrumenter::NotificationContext)
      @children = T.let({}, T::Hash[Symbol, InstrumentationContext])
    end

    def instrument_timing(operation, properties: {}, &_block)
      @store[operation] = properties
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield(properties)
    ensure
      finish_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      properties[:measured_start] = T.must(start_time)
      properties[:measured_finish] = finish_time
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
