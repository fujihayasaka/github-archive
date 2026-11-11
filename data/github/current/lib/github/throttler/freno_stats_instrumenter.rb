# typed: true
# frozen_string_literal: true

require "github/throttler/instrumenter"

module GitHub
  module Throttler
    class FrenoStatsInstrumenter < Instrumenter

      # responds to event "throttler.called"
      def called(payload)
        GitHub::FrenoInstrumenter.track_throttle_calls(cluster_names(payload))
      end

      # responds to event "throttler.waited_too_long"
      def waited_too_long(payload)
        clusters = cluster_names(payload)
        GitHub::FrenoInstrumenter.track_throttle_wait(payload[:waited], clusters)
        GitHub::FrenoInstrumenter.track_timeouts(clusters)
      end

      # responds to event "throttler.freno_errored"
      def freno_errored(payload)
        GitHub::FrenoInstrumenter.track_errors(cluster_names(payload))
      end

      # responds to event "throttler.succeeded"
      def succeeded(payload)
        GitHub::FrenoInstrumenter.track_throttle_wait(payload[:waited], cluster_names(payload))
      end

      # responds to event "throttler.circuit_open"
      def circuit_open(payload)
        clusters = cluster_names(payload)
        GitHub::FrenoInstrumenter.track_circuit_open_count(clusters)
        GitHub::FrenoInstrumenter.track_throttle_wait(payload[:waited], clusters)
      end

      private

      def cluster_names(payload)
        payload[:store_names] || []
      end
    end
  end
end
