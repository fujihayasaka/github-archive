# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsFeaturedSponsorshipsSettingsTest < GitHub::TestCase
  context "#initialize" do
    test "returns featured sponsorship settings with default value" do
      result = SponsorsFeaturedSponsorshipsSettings.new(bitmask: nil)
      assert_equal 0, result.bitmask
    end

    test "returns featured sponsorship settings with given value" do
      result = SponsorsFeaturedSponsorshipsSettings.new(bitmask: 3)
      assert_equal 3, result.bitmask
    end
  end

  test "returns bitmask with enabled bit enabled" do
    result = SponsorsFeaturedSponsorshipsSettings.new(bitmask: nil)
    result.enable
    assert_equal 1, result.bitmask
    assert result.enabled?
  end

  test "returns bitmask with automatic bit activated" do
    result = SponsorsFeaturedSponsorshipsSettings.new(bitmask: nil)
    result.automatic
    assert_equal 2, result.bitmask
    assert result.automatic?
  end

  test "returns bitmask with enabled bit and automatic bit activated" do
    result = SponsorsFeaturedSponsorshipsSettings.new(bitmask: nil)
    result.enable
    result.automatic
    assert_equal 3, result.bitmask
    assert result.enabled? && result.automatic?
  end
end
