# typed: true
# frozen_string_literal: true

require "github/throttler/instrumenter"

module GitHub
  module Throttler
    class DatadogInstrumenter < Instrumenter

      PREFIX = "github.throttler"

      attr_reader :datadog

      # instrumenter.instrument("throttler.#{event_name}", payload, &block
      def initialize(datadog: GitHub.dogstats)
        @datadog = datadog
      end

      # responds to event "throttler.called"
      def called(payload)
        datadog.increment(with_prefix("called"), tags: tags_from(payload))
      end

      # responds to event "throttler.waited"
      def waited(payload)
        datadog.distribution(with_prefix("waited"), payload[:waited], tags: tags_from(payload))
      end

      # responds to event "throttler.waited_too_long"
      def waited_too_long(payload)
        datadog.increment(with_prefix("timed_out"), tags: tags_from(payload))
      end

      # responds to event "throttler.freno_errored"
      def freno_errored(payload)
        datadog.increment(with_prefix("freno_error"), tags: tags_from(payload))
      end

      # responds to event "throttler.circuit_open"
      def circuit_open(payload)
        datadog.increment(with_prefix("circuit_open"), tags: tags_from(payload))
      end

      private

      def with_prefix(stat)
        "#{PREFIX}.#{stat}"
      end

      def tags_from(payload)
        cluster_names = payload[:store_names] || []
        cluster_tags = cluster_names.map { |cluster_name| "cluster:#{cluster_name}" }
        cluster_tags + ["throttler:freno"]
      end
    end
  end
end
