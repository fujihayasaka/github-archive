# frozen_string_literal: true
#              


require "vexi/instrumenter"
require "vexi/instrumentation_context"
require "vexi/observability/notification"

# Public: The main Vexi module for performing feature flag enabled checks.
module Vexi
  # Public: The notifications class is used by components to publish notifications for observability
  class Notifications
    attr_reader :instrumenter
    attr_reader :configuration_context

    def initialize(configuration_context = {}, instrumenter = Observability::Notification.new)
      @configuration_context =      (configuration_context                                            )
      @instrumenter =      (instrumenter              )
    end

    # Method instrument_error publishes an event under the name vexi.#{operation}.error whenever an error has occurred
    def instrument_error(operation, err, message:, context:)
      applied_context =      (context.merge!({
        operation: operation,
        message: message,
        error: err
      })                                   )
      applied_context[:config] = @configuration_context

      @instrumenter.instrument("vexi.#{operation}.error", applied_context)
    end

    # Method instrument_timing is a helper operation that wraps a block of code with timing
    # to call instrument_duration
    def instrument_timing(operation, properties: {}, &_block)
      instrumentation_context = InstrumentationContext.new(properties)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield(instrumentation_context)
    ensure
      time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      # It's possible that any of the lines above will be interrupted by a timeout error
      # To avoid raising exceptions in the consumer of these events, we should ensure
      # that the result of finish_time - start_time is exactly 0 so it can be filtered out
      start_time ||= time
      finish_time = time

      # Best-effort to preserve passed properties if object creation fails
      context_hash = instrumentation_context ? instrumentation_context.to_h : properties
      instrument_duration(operation, start_time, finish_time, context_hash)
    end

    # Method instrument_duration publishes an event under the name vexi.#{operation}.duration whenever
    # a operation timing has been measured.
    def instrument_duration(operation, measured_start, measured_finish, context)
      context[:operation] = operation
      context[:measured_start] = measured_start
      context[:measured_finish] = measured_finish
      context[:config] = @configuration_context

      @instrumenter.instrument("vexi.#{operation}.duration", context)
    end
  end
end
