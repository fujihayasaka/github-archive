# typed: true
# frozen_string_literal: true

require "test_helper"

module TasklistBlocks
  class ValidationErrorTest < GitHub::TestCase
    test "to_s" do
      error = ValidationError.new(0, 1, "error")
      assert_equal "error at block 1, line 2", error.to_s
    end
  end
end
