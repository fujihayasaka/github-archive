# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlocks::Operations::UpdateItemStateTest < GitHub::TestCase
  include DogstatsTestHelpers

  context "invalid input" do
    test "stats and does nothing when list is not found at position" do
      subject = TasklistBlocks::Operations::UpdateItemState.new(position: [1, 0], closed: false)
      md = <<~MD
      ```[tasklist]
      - [ ] foo
      - [ ] bar
      - [ ] baz
      ```
      MD
      assert_nil subject.call(md)
      assert_dogstats_increment(
        1,
        "tasklist_blocks.operation",
        tags: ["operation:UpdateItemState", "status:failure", "reason:no_tasklist_block_found"]
      )
    end

    test "does nothing when list if neither value or closed is passed in" do
      subject = TasklistBlocks::Operations::UpdateItemState.new(position: [0, 0], closed: nil)
      md = <<~MD
      ```[tasklist]
      - [ ] foo
      - [ ] bar
      - [ ] baz
      ```
      MD
      assert_nil subject.call(md)
    end
  end

  context "input handling" do
    test "changes draft title state" do
      subject = TasklistBlocks::Operations::UpdateItemState.new(position: [0, 0], closed: true)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] bar
      - [ ] baz
      ```
      MD
      result = subject.call(original)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [x] foo
      - [ ] bar
      - [ ] baz
      ```
      MD
      assert_equal expected, result
    end

    test "handles long titles" do
      long_title = SecureRandom.hex(160)
      subject = TasklistBlocks::Operations::UpdateItemState.new(position: [0, 1], closed: true)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] #{long_title}
      - [ ] bar
      - [ ] baz
      ```
      MD
      result = subject.call(original)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] #{long_title}
      - [x] bar
      - [ ] baz
      ```
      MD
      assert_equal expected, result
    end

    test "handles draft title state change for correct item when there are empty items in tasklist" do
      subject = TasklistBlocks::Operations::UpdateItemState.new(position: [0, 1], closed: true)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ]
      - [ ] bar
      - [ ] baz
      ```
      MD
      result = subject.call(original)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ]
      - [x] bar
      - [ ] baz
      ```
      MD
      assert_equal expected, result
    end

    test "update first list item state of first list at [0, 0]" do
      subject = TasklistBlocks::Operations::UpdateItemState.new(position: [0, 0], closed: false)
      original = <<~MD
      ```[tasklist]
      - [x] emperor's new foo
      - [ ] bar
      - [ ] baz
      ```

      - [ ] Other list

      ```[tasklist]
      - [ ] second list draft
      ```
      MD
      result = subject.call(original)
      expected_md = <<~MD
      ```[tasklist]
      - [ ] emperor's new foo
      - [ ] bar
      - [ ] baz
      ```

      - [ ] Other list

      ```[tasklist]
      - [ ] second list draft
      ```
      MD
      assert_equal expected_md, result
    end

    test "updates deeper list item draft title state in a second list at [1, 8]" do
      subject = TasklistBlocks::Operations::UpdateItemState.new(position: [1, 8], closed: true)
      original = <<~MD
      Some pre text before!

      ```[tasklist]
      - [ ] first list draft
      ```

      - [ ] Garrett
      - [ ] Randall

      ```[tasklist]
      - [ ] Hello world
      - [ ] #1
      - [ ] Test
      - [ ] Hello world
      - [ ] Hey max
      - [ ] Check this out
      - [ ] Hello!
      - [ ] My draft
      - [ ] Appending [ ] test
      - [ ] Hi Max
      - [ ] Hi Natasha
      ```

      One more modification.
      MD
      result = subject.call(original)

      expected_md = <<~MD
      Some pre text before!

      ```[tasklist]
      - [ ] first list draft
      ```

      - [ ] Garrett
      - [ ] Randall

      ```[tasklist]
      - [ ] Hello world
      - [ ] #1
      - [ ] Test
      - [ ] Hello world
      - [ ] Hey max
      - [ ] Check this out
      - [ ] Hello!
      - [ ] My draft
      - [x] Appending [ ] test
      - [ ] Hi Max
      - [ ] Hi Natasha
      ```

      One more modification.
      MD
      assert_equal expected_md, result
    end

    test "handles multi-byte characters for draft state updates updates" do
      subject = TasklistBlocks::Operations::UpdateItemState.new(position: [0, 1], closed: false)
      text = "```[tasklist]\r\n- [ ] ☃\r\n- [x] 😀\r\n```\r\n"
      result = subject.call(text)
      expected = <<~MD
      ```[tasklist]
      - [ ] ☃
      - [ ] 😀
      ```
      MD

      assert_equal expected, result
    end

    test "handles abnormal breaks for draft status updates" do
      subject = TasklistBlocks::Operations::UpdateItemState.new(position: [0, 2], closed: true)
      text = "```[tasklist]\r\n- [ ] a\r\n- [ ] b\r\n- [ ] c\r\n```\r\n"
      result = subject.call(text)
      expected = <<~MD
      ```[tasklist]
      - [ ] a
      - [ ] b
      - [x] c
      ```
      MD
      assert_equal expected, result
    end

    test "handles non-dash item prefixes" do
      subject = TasklistBlocks::Operations::UpdateItemState.new(position: [0, 0], closed: true)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      * [ ] foo
      ```
      MD
      result = subject.call(original)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      * [x] foo
      ```
      MD
      assert_equal expected, result

      original = <<~MD
      ```[tasklist]
      ### Tasks
      1. [ ] foo
      ```
      MD
      result = subject.call(original)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      1. [x] foo
      ```
      MD
      assert_equal expected, result

      original = <<~MD
      ```[tasklist]
      ### Tasks
      + [ ] foo
      ```
      MD
      result = subject.call(original)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      + [x] foo
      ```
      MD
      assert_equal expected, result
    end
  end
end
