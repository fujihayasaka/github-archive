# typed: strict
# frozen_string_literal: true

module OctoCore::Telemetry::Stats

  # Records all metrics to memory. Useful for testing.
  class Memory
    extend T::Sig
    extend T::Helpers

    include OctoCore::Telemetry::Stats

    class Stat < T::Struct
      const :stat, String
      const :value, Numeric
      const :tags, T::Array[String]
    end

    sig { void }
    def initialize
      @counts = T.let([], T::Array[Stat])
      @gauges = T.let([], T::Array[Stat])
      @distributions = T.let([], T::Array[Stat])
    end

    sig { override.params(stat: String, count: Numeric, tags: T::Array[String]).void }
    def count(stat, count, tags = EMPTY_TAGS)
      @counts << Stat.new(stat: stat, value: count, tags: tags)
    end

    sig { override.params(stat: String, value: Numeric, tags: T::Array[String]).void }
    def gauge(stat, value, tags = EMPTY_TAGS)
      @gauges << Stat.new(stat: stat, value: value, tags: tags)
    end

    sig { override.params(stat: String, value: Numeric, tags: T::Array[String]).void }
    def distribution(stat, value, tags = EMPTY_TAGS)
      @distributions << Stat.new(stat: stat, value: value, tags: tags)
    end

    sig { params(stat: String, tags: T::Array[String]).returns(Numeric) }
    def sum_counts(stat, tags = EMPTY_TAGS)
      @counts.select { |s| s.stat == stat && (tags.empty? || (tags - s.tags).empty?) }.sum(&:value)
    end

    sig { void }
    def clear
      @counts.clear
      @gauges.clear
      @distributions.clear
    end

    sig { returns(T::Array[Stat]) }
    attr_reader :counts

    sig { returns(T::Array[Stat]) }
    attr_reader :gauges

    sig { returns(T::Array[Stat]) }
    attr_reader :distributions
  end
end
