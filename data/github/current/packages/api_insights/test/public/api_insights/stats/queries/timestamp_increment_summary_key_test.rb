# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats::Queries
  class TimestampIncrementSummaryKeyTest < GitHub::TestCase
    test "initialization" do
      key = TimestampIncrementSummaryKey.new("1h")
      assert_equal "1h", key.timestamp_increment
    end

    test "initialization with invalid timespan" do
      error = assert_raises(Error) { TimestampIncrementSummaryKey.new("1 hour") }
      assert_equal ErrorCode::INVALID_TIMESTAMP_INCREMENT, error.code
    end

    test "to_s method" do
      key = TimestampIncrementSummaryKey.new("1h")
      assert_equal "bin(timestamp, timestamp_increment_param)", key.to_s
    end

    test "parameters method" do
      key = TimestampIncrementSummaryKey.new("1h")
      expected_params = {
        "timestamp_increment_param" => "1h"
      }
      assert_equal expected_params, key.parameters
    end
  end
end
