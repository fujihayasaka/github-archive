# typed: strict
# frozen_string_literal: true

require "datadog/statsd"

module OctoCore
  module Telemetry
    # This interface is used to record metrics. It is abstracted so that we can
    # easily swap out the underlying implementation.
    # Set the client to the desired implementation (e.g. `OctoCore::Telemetry::Stats::Datadog.new`)
    # and then use the `OctoCore::Telemetry::Stats.client` method to access it.
    module Stats
      extend T::Sig
      extend T::Helpers

      autoload :Datadog, "octo_core/telemetry/stats/datadog"
      autoload :Memory, "octo_core/telemetry/stats/memory"
      autoload :Null, "octo_core/telemetry/stats/null"
      autoload :Output, "octo_core/telemetry/stats/output"

      abstract!

      EMPTY_TAGS = T.let([].freeze, T::Array[String])

      @client = T.let(nil, T.nilable(Stats))
      sig { returns(Stats) }
      def self.client
        T.must(@client)
      end

      sig { params(client: Stats).void }
      def self.client=(client)
        @client = client
      end

      sig { returns(Numeric) }
      def self.monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      sig { params(start: Numeric).returns(Numeric) }
      def self.duration_since(start)
        ending = OctoCore::Telemetry::Stats.monotonic_time
        ((ending - start) * 1_000).round(5)
      end

      sig { abstract.params(stat: String, count: Numeric, tags: T::Array[String]).void }
      def count(stat, count, tags = EMPTY_TAGS); end

      sig { abstract.params(stat: String, value: Numeric, tags: T::Array[String]).void }
      def gauge(stat, value, tags = EMPTY_TAGS); end

      sig { abstract.params(stat: String, value: Numeric, tags: T::Array[String]).void }
      def distribution(stat, value, tags = EMPTY_TAGS); end

      sig { params(stat: String, tags: T::Array[String]).void }
      def increment(stat, tags = EMPTY_TAGS)
        count(stat, 1, tags)
      end

      sig { params(stat: String, tags: T::Array[String], block: T.proc.returns(T.untyped)).returns(T.untyped) }
      def distribution_time(stat, tags = EMPTY_TAGS, &block)
        start = OctoCore::Telemetry::Stats.monotonic_time
        yield
      ensure
        duration = OctoCore::Telemetry::Stats.duration_since(T.must(start))
        distribution(stat, duration, tags)
      end
    end
  end
end
