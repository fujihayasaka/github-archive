# typed: true
# frozen_string_literal: true

require "test_helper"

class SecretScanningProtobufTest < GitHub::TestCase
  context "Duration utils" do
    test "from_milliseconds" do
      assert_equal(
        Google::Protobuf::Duration.new(seconds: 0, nanos: 0),
        SecretScanning::Util::Protobuf::Duration.from_milliseconds(0)
      )
      assert_equal(
        Google::Protobuf::Duration.new(seconds: 0, nanos: 0),
        SecretScanning::Util::Protobuf::Duration.from_milliseconds(-1000)
      )
      assert_equal(
        Google::Protobuf::Duration.new(seconds: 0, nanos: 1_000_000),
        SecretScanning::Util::Protobuf::Duration.from_milliseconds(1)
      )
      assert_equal(
        Google::Protobuf::Duration.new(seconds: 1, nanos: 0),
        SecretScanning::Util::Protobuf::Duration.from_milliseconds(1000)
      )
      assert_equal(
        Google::Protobuf::Duration.new(seconds: 2, nanos: 500_000_000),
        SecretScanning::Util::Protobuf::Duration.from_milliseconds(2500)
      )
      assert_equal(
        Google::Protobuf::Duration.new(seconds: 5, nanos: 0),
        SecretScanning::Util::Protobuf::Duration.from_milliseconds(5000)
      )
    end
  end
end
