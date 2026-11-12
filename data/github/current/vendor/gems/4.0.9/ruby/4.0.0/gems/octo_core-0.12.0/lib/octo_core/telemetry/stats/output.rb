# typed: strict
# frozen_string_literal: true

module OctoCore::Telemetry::Stats

  # A standard out/error implementation of the Stats interface.
  class Output
    extend T::Sig
    extend T::Helpers

    include OctoCore::Telemetry::Stats

    sig { params(output: T.any(IO, StringIO)).void }
    def initialize(output: $stdout)
      @output = output
    end

    sig { override.params(stat: String, count: Numeric, tags: T::Array[String]).void }
    def count(stat, count, tags = EMPTY_TAGS)
      report "count", stat, count, tags
    end

    sig { override.params(stat: String, value: Numeric, tags: T::Array[String]).void }
    def gauge(stat, value, tags = EMPTY_TAGS)
      report "gauge", stat, value, tags
    end

    sig { override.params(stat: String, value: Numeric, tags: T::Array[String]).void }
    def distribution(stat, value, tags = EMPTY_TAGS)
      report "distribution", stat, value, tags
    end

    private

    sig { params(type: String, stat: String, value: Numeric, tags: T::Array[String]).void }
    def report(type, stat, value, tags)
      str = "#{type} reported: #{stat} #{value}"
      str << " " << tags.join(", ") unless tags.empty?
      @output.puts str
    end
  end
end
