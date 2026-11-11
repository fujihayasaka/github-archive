# typed: strict
# frozen_string_literal: true

module OctoCore::Telemetry::Stats

  # A null implementation of the Stats interface. Swallows all metrics.
  class Null
    extend T::Sig
    extend T::Helpers

    include OctoCore::Telemetry::Stats

    sig { override.params(stat: String, count: Numeric, tags: T::Array[String]).void }
    def count(stat, count, tags = EMPTY_TAGS); end

    sig { override.params(stat: String, value: Numeric, tags: T::Array[String]).void }
    def gauge(stat, value, tags = EMPTY_TAGS); end

    sig { override.params(stat: String, value: Numeric, tags: T::Array[String]).void }
    def distribution(stat, value, tags = EMPTY_TAGS); end
  end
end
