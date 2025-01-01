# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlockCommands::Result::ExtractPositionTest < GitHub::TestCase
  context "#data" do
    test "returns the data instance var when the action is :add" do
      result = klass.new(success: true, action: :add, data: 1)

      assert_equal 1, result.data
    end

    test "returns the data instance var by default" do
      result = klass.new(success: true, action: :any, data: 42)

      assert_equal 42, result.data
    end
  end

  context "#success?" do
    test "success" do
      result = klass.new(success: true, action: :add)

      assert_predicate result, :success?
    end

    test "failure" do
      result = klass.new(success: false, action: :add)

      refute_predicate result, :success?
    end
  end

  context "#message" do
    test "returns the message" do
      message = "hello world"
      result = klass.new(success: false, action: :add, message: message)

      assert_equal message, result.message
    end
  end

  private

  def klass
    TasklistBlockCommands::Result::ExtractPosition
  end
end
