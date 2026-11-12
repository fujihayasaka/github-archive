# typed: strict
# frozen_string_literal: true

module OctoCore
  module Middleware
    class Stats
      extend T::Sig

      sig { params(app: T.untyped).void }
      def initialize(app)
        @app = app
      end

      sig { params(env: T::Hash[String, T.untyped]).returns([Integer, T::Hash[String, String], String]).checked(:tests) }
      def call(env)
        start_cpu_time = cpu_thread_time
        start_time = OctoCore::Telemetry::Stats.monotonic_time

        result = @app.call(env)

        # include tag calculation time in reported request times
        tags = tags(env)

        end_time = OctoCore::Telemetry::Stats.monotonic_time
        cpu_ms = (cpu_thread_time - start_cpu_time) * 1000.0
        total_ms = (end_time - start_time) * 1000.0

        OctoCore::Telemetry::Stats.client.distribution("request.time.total", total_ms, tags)
        OctoCore::Telemetry::Stats.client.distribution("request.time.cpu", cpu_ms, tags)

        result
      end

      private

      # See https://github.com/github/github/pull/324413 for reasoning around reporting this metric instead
      # of process time.
      sig { returns(Numeric).checked(:tests) }
      def cpu_thread_time
        Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)
      end

      sig { params(env: T::Hash[String, T.untyped]).returns(T::Array[String]).checked(:tests) }
      def tags(env)
        endpoint = env["action_dispatch.request.path_parameters"]
        return [] unless endpoint

        controller = endpoint[:controller]
        action = endpoint[:action]

        tags = []
        tags << "controller:#{controller}" if controller
        tags << "action:#{action}" if action
        tags
      end
    end
  end
end
