# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::DecryptedTokenTest < GitHub::TestCase
  context "#to_s" do
    test "returns token value" do
      value = "foo"
      assert_equal value, Copilot::DecryptedToken.new(value: value).to_s
    end
  end

  context ".from" do
    test "wraps a token value in an DecryptedToken" do
      result = Copilot::DecryptedToken.from("foo")
      assert_instance_of Copilot::DecryptedToken, result
      assert_equal "foo", result.value
    end
  end

  context "#authorization_header_value" do
    test "includes necessary prefix for use in an Authorization header" do
      assert_equal "Bearer foo", Copilot::DecryptedToken.new(value: "foo").authorization_header_value
    end
  end
end
