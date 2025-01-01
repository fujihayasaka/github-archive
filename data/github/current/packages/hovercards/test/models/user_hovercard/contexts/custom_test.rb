# typed: true
# frozen_string_literal: true

require "test_helper"

class HovercardContextsCustomTest < GitHub::TestCase
  test "returns the message and octicon it is passed" do
    message = "hello world"
    octicon = "people"

    context = Hovercard::Contexts::Custom.new(message, octicon)

    assert_equal message, context.message
    assert_equal octicon, context.octicon
  end
end
