# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlockCommands::ResultTest < GitHub::TestCase
  context "#success?" do
    test "success" do
      result = klass.new(success: true)

      assert_predicate result, :success?
    end

    test "failure" do
      result = klass.new(success: false)

      refute_predicate result, :success?
    end
  end

  context "#message" do
    test "returns the message" do
      message = "hello world"
      result = klass.new(success: false, message: message)

      assert_equal message, result.message
    end
  end

  private

  def klass
    TasklistBlockCommands::Result
  end
end
