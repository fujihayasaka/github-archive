# typed: true
# frozen_string_literal: true

require "test_helper"

module CommandPalette
  class ActionTest < GitHub::TestCase
    test "has a type" do
      action = Action.new(type: :some_type, description: "some description", path: "/test/path")
      assert_equal :some_type, action.type
    end

    test "has a description" do
      action = Action.new(type: :some_type, description: "some description", path: "/test/path")
      assert_equal "some description", action.description
    end

    test "has a path" do
      action = Action.new(type: :some_type, description: "some description", path: "/test/path")
      assert_equal "/test/path", action.path
    end

    test "responds to #as_json" do
      action = Action.new(type: :some_type, description: "some description", path: "/test/path")
      assert action.respond_to?(:as_json)
    end

    test "returns the expected json" do
      action = Action.new(type: :some_type, description: "some description", path: "/test/path")
      assert_equal(
        { type: :some_type, description: "some description", path: "/test/path" },
        action.as_json
      )
    end
  end
end
