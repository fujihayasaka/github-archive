# typed: true
# frozen_string_literal: true

require "test_helper"

class HsbColorTest < GitHub::TestCase
  test "should be readable from a hex color" do
    hsb = Color::HSB.from_hex("ff0000")
    assert_equal 0, hsb.h
    assert_equal 1, hsb.s
    assert_equal 1, hsb.b

    hsb = Color::HSB.from_hex("#fff")
    assert_equal 0, hsb.h
    assert_equal 0, hsb.s
    assert_equal 1, hsb.b
  end

  test "should be round-trip convertible to hex" do
    assert_equal "ff0000", Color::HSB.from_hex("ff0000").to_hex
  end
end
