# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlocks::Operations::RemoveItemTest < GitHub::TestCase
  include DogstatsTestHelpers

  context "invalid input" do
    test "stats and does nothing when list is not found at position" do
      subject = TasklistBlocks::Operations::RemoveItem.new(position: [1, 0])
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
        tags: ["operation:RemoveItem", "status:failure", "reason:no_tasklist_block_found"]
      )
    end
  end

  context "input handling" do
    test "handles titles" do
      subject = TasklistBlocks::Operations::RemoveItem.new(position: [0, 0])
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
      - [ ] bar
      - [ ] baz
      ```
      MD
      assert_equal expected, result
    end

    test "handles long titles" do
      long_title = SecureRandom.hex(160)
      subject = TasklistBlocks::Operations::RemoveItem.new(position: [0, 1])
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
      - [ ] baz
      ```
      MD
      assert_equal expected, result
    end

    test "removes first list item of first list at [0, 0]" do
      subject = TasklistBlocks::Operations::RemoveItem.new(position: [0, 0])
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

    test "removes the correct list item ignoring empty items" do
      subject = TasklistBlocks::Operations::RemoveItem.new(position: [0, 1])
      original = <<~MD
      ```[tasklist]
      - [ ] foo
      - [ ]
      - [ ] bar
      - [ ]
      - [ ] baz
      ```
      MD
      result = subject.call(original)
      expected_md = <<~MD
      ```[tasklist]
      - [ ] foo
      - [ ]
      - [ ]
      - [ ] baz
      ```
      MD
      assert_equal expected_md, result
    end

    test "removes deeper list item in a second list at [1, 8]" do
      subject = TasklistBlocks::Operations::RemoveItem.new(position: [1, 8])
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
      - [ ] Hi Max
      - [ ] Hi Natasha
      ```

      One more modification.
      MD
      assert_equal expected_md, result
    end

    test "handles multi-byte characters" do
      subject = TasklistBlocks::Operations::RemoveItem.new(position: [0, 1])
      text = "```[tasklist]\r\n- [ ] ☃\r\n- [ ] 😀\r\n```\r\n"
      result = subject.call(text)
      expected = <<~MD
      ```[tasklist]
      - [ ] ☃
      ```
      MD
      assert_equal expected, result
    end

    test "handles abnormal breaks" do
      subject = TasklistBlocks::Operations::RemoveItem.new(position: [0, 2])
      text = "```[tasklist]\r\n- [ ] a\r\n- [ ] b\r\n- [ ] c\r\n```\r\n"
      result = subject.call(text)
      expected = <<~MD
      ```[tasklist]
      - [ ] a
      - [ ] b
      ```
      MD
      assert_equal expected, result
    end
  end
end
