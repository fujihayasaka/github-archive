# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats::Queries
  class TimestampIncrementSummaryKey
    include Kusto::Data::KQL

    TIMESTAMP_INCREMENT_PARAMETER_NAME = "timestamp_increment_param"
    private_constant :TIMESTAMP_INCREMENT_PARAMETER_NAME

    sig { returns(String) }
    attr_reader :timestamp_increment

    sig { params(timestamp_increment: String).void }
    def initialize(timestamp_increment)
      raise Error.new(ErrorCode::INVALID_TIMESTAMP_INCREMENT, timestamp_increment:) unless timespan?(timestamp_increment)

      @timestamp_increment = timestamp_increment
    end

    sig { returns(String) }
    def to_s
      "bin(timestamp, #{TIMESTAMP_INCREMENT_PARAMETER_NAME})"
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def parameters
      {
        TIMESTAMP_INCREMENT_PARAMETER_NAME => @timestamp_increment
      }
    end
  end
end
