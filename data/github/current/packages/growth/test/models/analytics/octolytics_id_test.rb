# typed: true
# frozen_string_literal: true

require "test_helper"
require "active_support/core_ext"

module Analytics
  class OctolyticsIdTest < GitHub::TestCase
    context ".generate" do
      test "creates a new ID with a version, random int and timestamp " do
        pattern = /\A
          GH1.1     # version
          .\d{2,10} # random 32-bit int
          .\d{2,10} # timestamp
        \Z/x

        assert_match pattern, OctolyticsId.generate.to_s
      end

      test "generates unique IDs" do
        refute_equal OctolyticsId.generate.to_s, OctolyticsId.generate.to_s
      end
    end

    context ".coerce" do
      test "coerces strings" do
        id = OctolyticsId.new(
          version: "GH1.1",
          value: "1784622427",
          timestamp: "1449520462",
        )
        coerced = OctolyticsId.coerce("GH1.1.1784622427.1449520462")

        assert_equal id, coerced
      end

      test "coerces ints" do
        id = OctolyticsId.coerce(7664894961122667854)
        assert_equal "GH1.1.1784622427.1449520462", id.to_s
      end

      test "raises an error when the components are missing" do
        assert_raises OctolyticsId::CoercionError do
          OctolyticsId.coerce("1.1.1784622427.1449520462")
        end
      end

      test "raises an when ints are out of range" do
        assert_raises OctolyticsId::CoercionError do
          OctolyticsId.coerce(2**65)
        end
      end

      test "raises an error when it receives garbage" do
        assert_raises OctolyticsId::CoercionError do
          OctolyticsId.coerce("SNAKEPOISON")
        end
      end

      test "raises an error when it receives a string with invalid UTF-8" do
        assert_raises OctolyticsId::CoercionError do
          OctolyticsId.coerce("hi \255")
        end
      end
    end

    context "#to_i" do
      test "concats the value and timestamp" do
        id = OctolyticsId.new(
          version: "GH1.1",
          value: "1784622427",
          timestamp: "1449520462",
        )
        assert_equal 7664894961122667854, id.to_i
      end
    end

    context "#to_s" do
      test "composes the version, value and timestamp" do
        id = OctolyticsId.new(
          version: "GH1.1",
          value: "1784622427",
          timestamp: "1449520462",
        )
        assert_equal "GH1.1.1784622427.1449520462", id.to_s
      end
    end

    context "#unversioned" do
      test "composes the value and timestamp" do
        id = OctolyticsId.new(
          version: "GH1.1",
          value: "1784622427",
          timestamp: "1449520462",
        )
        assert_equal "1784622427.1449520462", id.unversioned
      end
    end

    context "#==" do
      test "is true when the version, value and timestamp match" do
        id = OctolyticsId.new(
          version: "GH1.1",
          value: "1784622427",
          timestamp: "1449520462",
        )

        assert_equal OctolyticsId.new(
          version: "GH1.1",
          value: "1784622427",
          timestamp: "1449520462",
        ), id

        refute_equal OctolyticsId.new(
          version: "GH1.2",
          value: "1784622427",
          timestamp: "1449520462",
        ), id

        refute_equal OctolyticsId.new(
          version: "GH1.1",
          value: "4045444523",
          timestamp: "1449520462",
        ), id

        refute_equal OctolyticsId.new(
          version: "GH1.1",
          value: "1784622427",
          timestamp: "1449520000",
        ), id
      end
    end

    test "exposes components" do
      id = OctolyticsId.new(
        version: "GH1.1",
        value: "1784622427",
        timestamp: "1449520462",
      )

      assert_equal id.version, "GH1.1"
      assert_equal id.value, 1784622427
      assert_equal id.timestamp, 1449520462
    end
  end
end
