# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlocks::Operations::UpdateItemTitleTest < GitHub::TestCase
  include DogstatsTestHelpers

  context "invalid input" do
    test "stats and does nothing when list is not found at position" do
      subject = TasklistBlocks::Operations::UpdateItemTitle.new(position: [1, 0], value: "new value")
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
        tags: ["operation:UpdateItemTitle", "status:failure", "reason:no_tasklist_block_found"]
      )
    end

    test "does nothing when list if neither value or closed is passed in" do
      subject = TasklistBlocks::Operations::UpdateItemTitle.new(position: [0, 0], value: nil)
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
    test "handles titles" do
      subject = TasklistBlocks::Operations::UpdateItemTitle.new(position: [0, 0], value: "emperor's new foo")
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
      - [ ] emperor's new foo
      - [ ] bar
      - [ ] baz
      ```
      MD
      assert_equal expected, result
    end

    test "handles long titles" do
      long_title = SecureRandom.hex(160)
      subject = TasklistBlocks::Operations::UpdateItemTitle.new(position: [0, 1], value: "emperor's new foo")
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
      - [ ] emperor's new foo
      - [ ] baz
      ```
      MD
      assert_equal expected, result
    end

    test "handles updating title state change for correct item when there are empty items in tasklist" do
      subject = TasklistBlocks::Operations::UpdateItemTitle.new(position: [0, 1], value: "emperor's new foo")
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ]
      - [ ] baz
      ```
      MD
      result = subject.call(original)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ]
      - [ ] emperor's new foo
      ```
      MD
      assert_equal expected, result
    end

    test "update first list item text of first list at [0, 0]" do
      subject = TasklistBlocks::Operations::UpdateItemTitle.new(position: [0, 0], value: "emperor's new foo")
      original = <<~MD
      ```[tasklist]
      - [ ] foo
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

    test "update preserves item state" do
      subject = TasklistBlocks::Operations::UpdateItemTitle.new(position: [0, 0], value: "emperor's new foo")
      original = <<~MD
      ```[tasklist]
      - [x] foo
      - [ ] bar
      - [x] baz
      ```

      - [ ] Other list

      ```[tasklist]
      - [ ] second list draft
      ```
      MD
      result = subject.call(original)
      expected_md = <<~MD
      ```[tasklist]
      - [x] emperor's new foo
      - [ ] bar
      - [x] baz
      ```

      - [ ] Other list

      ```[tasklist]
      - [ ] second list draft
      ```
      MD
      assert_equal expected_md, result
    end

    test "updates deeper list item draft title text in a second list at [1, 8]" do
      subject = TasklistBlocks::Operations::UpdateItemTitle.new(position: [1, 8], value: "emperor's new foo")
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
      - [ ] emperor's new foo
      - [ ] Hi Max
      - [ ] Hi Natasha
      ```

      One more modification.
      MD
      assert_equal expected_md, result
    end

    test "handles multi-byte characters for draft title updates" do
      subject = TasklistBlocks::Operations::UpdateItemTitle.new(position: [0, 1], value: "emperor's new foo")
      text = "```[tasklist]\r\n- [ ] ☃\r\n- [ ] 😀\r\n```\r\n"
      result = subject.call(text)
      expected = <<~MD
      ```[tasklist]
      - [ ] ☃
      - [ ] emperor's new foo
      ```
      MD
      assert_equal expected, result
    end

    test "handles abnormal breaks for draft title updates" do
      subject = TasklistBlocks::Operations::UpdateItemTitle.new(position: [0, 2], value: "emperor's new foo")
      text = "```[tasklist]\r\n- [ ] a\r\n- [ ] b\r\n- [ ] c\r\n```\r\n"
      result = subject.call(text)
      expected = <<~MD
      ```[tasklist]
      - [ ] a
      - [ ] b
      - [ ] emperor's new foo
      ```
      MD
      assert_equal expected, result
    end

    test "handles non-dash item prefixes" do
      subject = TasklistBlocks::Operations::UpdateItemTitle.new(position: [0, 0], value: "emperor's new foo")
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
      * [ ] emperor's new foo
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
      1. [ ] emperor's new foo
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
      + [ ] emperor's new foo
      ```
      MD
      assert_equal expected, result
    end
  end
end
