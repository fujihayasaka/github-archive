# typed: true
# frozen_string_literal: true

require "test_helper"

module TasklistBlocks
  class TasklistBlockTest < GitHub::TestCase
    test "accessors" do
      block = TasklistBlocks::TasklistBlock.new

      assert_equal "Tasks", block.name
      assert_equal [], block.items
    end

    test "has properties if provided" do
      issue = TasklistBlocks::IssueReference.new(issue: create(:issue))
      block = TasklistBlocks::TasklistBlock.new(name: "My Tasks", items: [issue])

      assert_equal "My Tasks", block.name
      assert_equal [issue], block.items
    end
  end
end
