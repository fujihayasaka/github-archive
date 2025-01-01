# typed: true
# frozen_string_literal: true

require_relative "../../fast_test_helper"

class Localization::MoneyFormatter::NearestIntegerRoundingStrategyTest < GitHub::TestCase
  def round(value)
    Localization::MoneyFormatter::NearestIntegerRoundingStrategy.new.round(value)
  end

  test "rounds to the nearest when number has length > 2" do
    expectations = {
      110.21 => 110,
      99.21 => 99,
      4 => 4,
      10.9 => 11,
      3.36 => 3.36,
      2.87 => 2.87,
      296.74 => 297,
      290.84 => 291,
      21 => 21,
      17.62 => 18,
      15.07 => 15,
      1557.90 => 1558,
      1526.98 => 1527
    }.freeze

    expectations.each do |original, expected|
      rounded = round(original)
      msg = "expected #{original} to be rounded to #{expected} but it was rounded to #{rounded}"

      assert_equal(expected, rounded, msg)
    end
  end
end
