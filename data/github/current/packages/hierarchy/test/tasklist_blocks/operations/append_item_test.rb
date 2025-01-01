# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlocks::Operations::AppendItemTest < GitHub::TestCase
  include DogstatsTestHelpers

  context "invalid input" do
    test "stats and does nothing when list is not found" do
      subject = TasklistBlocks::Operations::AppendItem.new(position: 1, value: "b")
      assert_nil subject.call("```[tasklist]\n- [ ] a\n```\n")

      assert_dogstats_increment(
        1,
        "tasklist_blocks.operation",
        tags: ["operation:AppendItem", "status:failure", "reason:no_tasklist_block_found"]
      )
    end
  end

  context "input handling" do
    test "does not alter input string" do
      subject = TasklistBlocks::Operations::AppendItem.new(position: 0, value: "b")
      original = "```[tasklist]\n- [ ] a\n```\n\n- [ ] Other tasklist"
      result = subject.call(original)
      assert_equal "```[tasklist]\n- [ ] a\n- [ ] b\n```\n\n- [ ] Other tasklist", result
      assert_equal "```[tasklist]\n- [ ] a\n```\n\n- [ ] Other tasklist", original
    end

    test "appends item" do
      subject = TasklistBlocks::Operations::AppendItem.new(position: 0, value: "ohai")
      original = <<~MD
      ```[tasklist]
      - [ ] foo
      - [ ] bar
      ```
      MD
      result = subject.call(original)
      expected = <<~MD
      ```[tasklist]
      - [ ] foo
      - [ ] bar
      - [ ] ohai
      ```
      MD
      assert_equal expected, result
    end

    test "handles titles" do
      subject = TasklistBlocks::Operations::AppendItem.new(position: 0, value: "ohai")
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] bar
      ```
      MD
      result = subject.call(original)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] bar
      - [ ] ohai
      ```
      MD
      assert_equal expected, result
    end

    test "handles multi-byte characters" do
      subject = TasklistBlocks::Operations::AppendItem.new(position: 0, value: "✅")
      text = "```[tasklist]\r\n- [ ] ☃\r\n- [ ] 😀\r\n```\r\n"
      result = subject.call(text)

      expected = "```[tasklist]\n- [ ] ☃\n- [ ] 😀\n- [ ] ✅\n```\n"
      assert_equal expected, result
    end

    test "handles abnormal breaks" do
      subject = TasklistBlocks::Operations::AppendItem.new(position: 0, value: "c")
      text = "```[tasklist]\r- [ ] a\r- [ ] b\r```\r"
      result = subject.call(text)
      expected = "```[tasklist]\n- [ ] a\n- [ ] b\n- [ ] c\n```\n"
      assert_equal expected, result
    end

    test "handles non-dash item prefixes" do
      subject = TasklistBlocks::Operations::AppendItem.new(position: 0, value: "c")
      text = "```[tasklist]\r* [ ] a\r* [ ] b\r```\r"
      result = subject.call(text)
      expected = "```[tasklist]\n* [ ] a\n* [ ] b\n* [ ] c\n```\n"
      assert_equal expected, result

      subject = TasklistBlocks::Operations::AppendItem.new(position: 0, value: "c")
      text = "```[tasklist]\r1. [ ] a\r2. [ ] b\r```\r"
      result = subject.call(text)
      expected = "```[tasklist]\n1. [ ] a\n2. [ ] b\n1. [ ] c\n```\n"
      assert_equal expected, result

      subject = TasklistBlocks::Operations::AppendItem.new(position: 0, value: "c")
      text = "```[tasklist]\r+ [ ] a\r+ [ ] b\r```\r"
      result = subject.call(text)
      expected = "```[tasklist]\n+ [ ] a\n+ [ ] b\n+ [ ] c\n```\n"
      assert_equal expected, result

      # multiple tasklists with multiple prefix types
      subject = TasklistBlocks::Operations::AppendItem.new(position: 1, value: "c")
      text = "```[tasklist]\r+ [ ] a\r```\r```[tasklist]\r* [ ] b\r```\r"
      result = subject.call(text)
      expected = "```[tasklist]\n+ [ ] a\n```\n```[tasklist]\n* [ ] b\n* [ ] c\n```\n"
      assert_equal expected, result
    end
  end
end
