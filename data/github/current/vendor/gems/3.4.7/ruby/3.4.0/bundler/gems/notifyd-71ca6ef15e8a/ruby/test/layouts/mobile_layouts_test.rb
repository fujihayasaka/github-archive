# typed: true
# frozen_string_literal: true

require "test_helper"

class MobileLayoutsTest < Minitest::Test
  def test_has_basic_layout
    layout_data = Notifyd::Proto::Layouts::Mobile::Basic.new(
      url: "http://example.com/",
      title: "The title",
      subtitle: "The subtitle",
      body: "The body",
    )

    assert_equal "http://example.com/", layout_data.url
    assert_equal "The title", layout_data.title
    assert_equal "The subtitle", layout_data.subtitle
    assert_equal "The body", layout_data.body
  end
end
