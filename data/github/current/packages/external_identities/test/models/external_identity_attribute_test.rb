# typed: true
# frozen_string_literal: true

require "test_helper"

class ExternalIdentityAttributeTest < GitHub::TestCase
  fixtures do
    @metadata = { "primary" => true }
    @short_value = "test-value"
    @long_value = "t" * 256
    @raw_value = "test-raw-value"
    @unicode_short_value = "இந்திரஜித்"
    @unicode_long_value = "இ" * 86
  end

  context "#value" do
    test "returns raw_value if raw_value is set" do
      value_digest = ExternalIdentityAttribute.generate_value_digest(@raw_value)
      attribute = ExternalIdentityAttribute.new value: value_digest, raw_value: @raw_value

      assert_equal @raw_value, attribute.value
    end

    test "returns value if raw_value is not set" do
      attribute = ExternalIdentityAttribute.new value: @short_value

      assert_equal @short_value, attribute.value
      assert_nil attribute.raw_value
    end
  end

  context "#value=" do
    test "stores value in value field if the byte size is less than to equal to 255" do
      attribute = ExternalIdentityAttribute.new value: @short_value

      assert_equal @short_value, attribute.value
      assert_nil attribute.raw_value
    end

    test "stores value in raw_value field and hash of raw_value in value if the byte size is greater than 255" do
      value_digest = ExternalIdentityAttribute.generate_value_digest(@long_value)
      attribute = ExternalIdentityAttribute.new value: @long_value

      assert_equal @long_value, attribute.raw_value
      assert_equal @long_value, attribute.value
      assert_equal value_digest, attribute.read_attribute(:value)
    end

    test "stores unicode value in value field if the byte size is less than to equal to 255" do
      attribute = ExternalIdentityAttribute.new value: @unicode_short_value

      assert_equal @unicode_short_value, attribute.value
      assert_nil attribute.raw_value
    end

    test "stores unicode value in raw_value field and hash of raw_value in value field if the byte size is greater than 255" do
      value_digest = ExternalIdentityAttribute.generate_value_digest(@unicode_long_value)
      attribute = ExternalIdentityAttribute.new value: @unicode_long_value

      assert_equal @unicode_long_value, attribute.raw_value
      assert_equal @unicode_long_value, attribute.value
      assert_equal value_digest, attribute.read_attribute(:value)
    end
  end

  context "#metadata" do
    test "returns an empty hash if metadata_json is empty" do
      attribute = ExternalIdentityAttribute.new \
        metadata_json: nil

      assert_equal Hash.new, attribute.metadata

      attribute = ExternalIdentityAttribute.new \
        metadata_json: ""

      assert_equal Hash.new, attribute.metadata
    end

    test "returns the parsed value from metadata_json" do
      attribute = ExternalIdentityAttribute.new \
        metadata_json: @metadata.to_json

      assert_equal @metadata, attribute.metadata
    end
  end

  context "#metadata=" do
    test "stores serialized metadata in metadata_json" do
      attribute = ExternalIdentityAttribute.new
      attribute.metadata = @metadata

      assert_equal @metadata.to_json, attribute.metadata_json
    end

    test "clears metadata_json if passed nil" do
      attribute = ExternalIdentityAttribute.new \
        metadata_json: @metadata.to_json

      attribute.metadata = nil
      assert_nil attribute.metadata_json
    end

    test "raises an ArgumentError if not passed a Hash or nil" do
      attribute = ExternalIdentityAttribute.new

      assert_raises(ArgumentError) do
        attribute.metadata = "invalid"
      end
    end
  end
end
