# typed: true
# frozen_string_literal: true

require "test_helper"

class EmailLayoutsTest < Minitest::Test
  def test_has_basic_layout
    layout_data = Notifyd::Proto::Layouts::Email::Basic.new(
      subject: "The title",
      body: "The body",
    )

    assert_equal "The title", layout_data.subject
    assert_equal "The body", layout_data.body
  end
end
