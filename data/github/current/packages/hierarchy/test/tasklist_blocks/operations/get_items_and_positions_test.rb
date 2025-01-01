# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlocks::Operations::GetItemsAndPositionsTest < GitHub::TestCase
  context "input handling" do
    test "handles draft items and references" do
      subject = TasklistBlocks::Operations::GetItemsAndPositions.new
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] #1
      - [ ] bar
      - [ ] #{GitHub.url}/foo/bar/issues/2
      ```
      MD
      result = subject.call(original)
      assert_equal [[
        TasklistBlocks::ItemWithPosition.new(position: [0, 0], text: "foo"),
        TasklistBlocks::ItemWithPosition.new(position: [0, 1], text: "#1"),
        TasklistBlocks::ItemWithPosition.new(position: [0, 2], text: "bar"),
        TasklistBlocks::ItemWithPosition.new(position: [0, 3], text: "#{GitHub.url}/foo/bar/issues/2"),
      ]], result
    end

    test "returns correct position ignoring empty items" do
      subject = TasklistBlocks::Operations::GetItemsAndPositions.new
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] #1
      - [ ]
      - [ ] bar
      - [ ]
      - [ ] #{GitHub.url}/foo/bar/issues/2
      ```
      MD
      result = subject.call(original)
      assert_equal [[
        TasklistBlocks::ItemWithPosition.new(position: [0, 0], text: "foo"),
        TasklistBlocks::ItemWithPosition.new(position: [0, 1], text: "#1"),
        TasklistBlocks::ItemWithPosition.new(position: [0, 2], text: "bar"),
        TasklistBlocks::ItemWithPosition.new(position: [0, 3], text: "#{GitHub.url}/foo/bar/issues/2"),
      ]], result
    end

    test "handles multiple tasklist blocks" do
      subject = TasklistBlocks::Operations::GetItemsAndPositions.new
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] bar
      ```

      ```[tasklist]
      ### Tasks
      - [ ] baz
      - [ ] qux
      ```
      MD
      result = subject.call(original)
      assert_equal [[
        TasklistBlocks::ItemWithPosition.new(position: [0, 0], text: "foo"),
        TasklistBlocks::ItemWithPosition.new(position: [0, 1], text: "bar"),
      ], [
        TasklistBlocks::ItemWithPosition.new(position: [1, 0], text: "baz"),
        TasklistBlocks::ItemWithPosition.new(position: [1, 1], text: "qux"),
      ]], result
    end

    test "handles long titles" do
      long_title = SecureRandom.hex(160)
      subject = TasklistBlocks::Operations::GetItemsAndPositions.new
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] #{long_title}
      - [ ] bar
      - [ ] #{GitHub.url}/foo/bar/issues/2
      ```
      MD
      result = subject.call(original)
      assert_equal [[
        TasklistBlocks::ItemWithPosition.new(position: [0, 0], text: "foo"),
        TasklistBlocks::ItemWithPosition.new(position: [0, 1], text: long_title),
        TasklistBlocks::ItemWithPosition.new(position: [0, 2], text: "bar"),
        TasklistBlocks::ItemWithPosition.new(position: [0, 3], text: "#{GitHub.url}/foo/bar/issues/2"),
      ]], result
    end
  end
end

class ItemWithPositionTest < GitHub::TestCase
  context "==" do
    test "same item" do
      item = TasklistBlocks::ItemWithPosition.new(text: "", position: [0, 0])
      other_item = TasklistBlocks::ItemWithPosition.new(text: "", position: [0, 0])
      assert_equal item, other_item
    end

    test "different text" do
      item = TasklistBlocks::ItemWithPosition.new(text: "", position: [0, 0])
      other_item = TasklistBlocks::ItemWithPosition.new(text: "different", position: [0, 0])
      refute_equal item, other_item
    end

    test "different position" do
      item = TasklistBlocks::ItemWithPosition.new(text: "", position: [0, 0])
      other_item = TasklistBlocks::ItemWithPosition.new(text: "", position: [0, 1])
      refute_equal item, other_item
    end
  end

  context "does_match_issue?" do
    test "does match number" do
      issue = create(:issue, number: 2)
      item = TasklistBlocks::ItemWithPosition.new(text: "#2", position: [0, 0])
      assert item.does_match_issue?(issue)
    end
    test "does match url" do
      issue = create(:issue, number: 2)
      item = TasklistBlocks::ItemWithPosition.new(text: issue.url, position: [0, 0])
      assert item.does_match_issue?(issue)
    end
    test "does match nwo and number" do
      issue = create(:issue, number: 2)
      item = TasklistBlocks::ItemWithPosition.new(text: "#{issue.repository.nwo}##{issue.number}", position: [0, 0])
      assert item.does_match_issue?(issue)
    end
    test "does not match" do
      issue = create(:issue, number: 1)
      item = TasklistBlocks::ItemWithPosition.new(text: "#2", position: [0, 0])
      refute item.does_match_issue?(issue)
    end
  end
end
