# typed: true
# frozen_string_literal: true

require "test_helper"

class ColorCalculatorTest < GitHub::TestCase
  context "#readable_with?" do
    test "true for colors with a contrast greater than TARGET_CONTRAST" do
      calculator = ColorCalculator.new("000000")
      assert calculator.readable_with?("ffffff")
    end

    test "false for colors with a contrast less than TARGET_CONTRAST" do
      calculator = ColorCalculator.new("000000")
      refute calculator.readable_with?("333333")
    end
  end

  context "#contrast_with" do
    test "returns contrast between color and given color" do
      calculator = ColorCalculator.new("ff0000")
      assert_equal 3.43, calculator.contrast_with("ffeea1").round(2)
    end
  end

  context "#text_color" do
    test "returns readable hex color for a medium green background" do
      assert_readable_text_color_for "6d980e"
    end

    test "returns readable hex color for a dark olive background" do
      assert_readable_text_color_for "676517"
    end

    test "returns readable hex color for a light yellow background" do
      assert_readable_text_color_for "fceba1"
    end

    test "returns readable hex color for a dark gray background" do
      assert_readable_text_color_for "333333"
    end

    test "returns readable hex color for a dark purple background" do
      assert_readable_text_color_for "2E066D"
    end

    test "returns readable hex color for a light blue-gray background" do
      assert_readable_text_color_for "D6DDE7"
    end

    test "returns readable hex color for a bright green background" do
      assert_readable_text_color_for "64e00b"
    end

    test "returns white for a black background" do
      assert_equal "ffffff", ColorCalculator.new("000000").text_color
    end

    test "returns black for a white background" do
      assert_equal "000000", ColorCalculator.new("ffffff").text_color
    end
  end

  def assert_readable_text_color_for(background_color)
    calculator = ColorCalculator.new(background_color)
    text_color = calculator.text_color
    contrast = calculator.contrast_with(text_color)
    assert calculator.readable_with?(text_color),
      "#{background_color} and #{text_color} have a contrast of #{contrast}; suggested: " \
      "#{ColorCalculator::FALLBACK_CONTRAST}"
  end
end
