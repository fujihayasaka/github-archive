# typed: true
# frozen_string_literal: true

require "test_helper"

class StatusCheckConfig::ConclusionTest < GitHub::TestCase
  test "returns the proper conclusion icon class" do
    color = "color"
    conclusion_config = StatusCheckConfig::Conclusion.new(check_icon_color_class: color)

    assert_equal conclusion_config.check_icon_class, "#{color} selected-color-white"
  end
end
