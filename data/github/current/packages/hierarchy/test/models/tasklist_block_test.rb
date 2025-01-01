# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlocksTest < GitHub::TestCase
  include IssuesGraphTestHelpers

  test "aliases title and name" do
    block = TasklistBlock.new(
      parent_issue: TasklistBlocks::Issue.new(title: "foo", state: "open"),
      key: TasklistBlocks::Key.new(
        owner_id: 111,
        item_id: 222,
        primary_key: build_proto_primary_key
      ),
      order: 100,
      name: "My Title",
      items: []
    )
    assert_equal block.title, block.name
  end
end
