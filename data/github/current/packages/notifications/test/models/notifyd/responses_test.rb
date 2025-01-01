# typed: true
# frozen_string_literal: true

require "test_helper"

class NotifydResponsesBooleanTest < GitHub::TestCase
  test "defaults value to false" do
    response = Notifyd::Responses::Boolean.new
    assert_equal false, response.value
  end

  test "value? returns true for true" do
    response = Notifyd::Responses::Boolean.new { true }
    assert_equal true, response.value
  end

  test "value? returns false for false" do
    response = Notifyd::Responses::Boolean.new { false }
    assert_equal false, response.value
  end
end
