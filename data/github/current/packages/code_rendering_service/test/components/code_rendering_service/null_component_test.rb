# typed: true
# frozen_string_literal: true
require "test_helper"

class NullComponentTest < GitHub::TestCase
  test "ensure methods produce correct response" do
    view_component = CodeRenderingService::NullComponent.new

    assert_equal(view_component.view_type, :unsupported)
    assert_nil(view_component.render_type)
    assert_equal(view_component.supports_view?, false)
    assert_equal(view_component.is_notebook?, false)
  end
end
