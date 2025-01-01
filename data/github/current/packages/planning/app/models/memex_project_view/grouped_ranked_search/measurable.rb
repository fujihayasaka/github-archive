# typed: true
# frozen_string_literal: true

class MemexProjectView
  class GroupedRankedSearch
    # A proxy mix-in that will allow individual methods to be benchmarked for their runtime.  This can be turned on
    # by calling measure! within the class.
    module Measurable
      MEASURABLE_ROUND_TO = 2

      private_constant :MEASURABLE_ROUND_TO

      private

      def measure!
        @measurable = true

        self
      end

      def measure?
        @measurable || false
      end

      def dont_measure?
        !measure?
      end

      def measurable_results_in_ms
        @measurable_results_in_ms || {}
      end

      def add_measurement(method_name, time_in_ms)
        @measurable_results_in_ms ||= {}

        measurable_results_in_ms[method_name.to_sym] = time_in_ms.round(MEASURABLE_ROUND_TO)

        self
      end

      def measurable_execute(method_name, *args)
        return send(*T.unsafe([method_name, *args])) if dont_measure?

        output = T.let(nil, T.untyped)

        time_in_ms = Benchmark.realtime { output = send(*T.unsafe([method_name, *args])) } * 1000

        add_measurement(method_name, time_in_ms)

        output
      end

      def measurable_total_in_ms
        measurable_results_in_ms.values.sum.round(MEASURABLE_ROUND_TO)
      end
    end
  end
end
