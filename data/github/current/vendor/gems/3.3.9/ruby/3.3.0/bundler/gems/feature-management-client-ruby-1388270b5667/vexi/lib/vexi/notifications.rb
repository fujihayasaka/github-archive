# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"
require "vexi/instrumenter"
require "vexi/instrumentation_context"
require "vexi/observability/notification"

# Public: The main Vexi module for performing feature flag enabled checks.
module Vexi
  # Public: The notifications class is used by components to publish notifications for observability
  class Notifications
    class << self
      attr_accessor :instrumenter
      attr_accessor :configuration_context

      def initialize
        @instrumenter = T.let(Observability::Notification.new, Instrumenter)
        @configuration_context = T.let({}, T::Hash[Symbol, T.any(String, T::Boolean)])
      end

      # Method instrument_error publishes an event under the name vexi.#{operation}.error whenever an error has occurred
      def instrument_error(operation, err, message:, context:)
        applied_context = T.let(context.merge!({
          operation: operation,
          message: message,
          error: err
        }), Instrumenter::NotificationContext)
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
        finish_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        instrument_duration(operation, T.must(start_time), finish_time, instrumentation_context.to_h)
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

    # use ActiveSupport::Notifications as the default instrumentation service
    Notifications.instrumenter = Observability::Notification.new
    Notifications.configuration_context = {}
  end
end
