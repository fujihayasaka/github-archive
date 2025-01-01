# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlocks::Operations::RemoveTasklistBlockTest < GitHub::TestCase
  context "invalid input" do
    test "does nothing when list is not found" do
      subject = TasklistBlocks::Operations::RemoveTasklistBlock.new(position: 1)
      assert_nil subject.call("```[tasklist]\n- [ ] a\n```\n")
    end
  end

  context "input handling" do
    test "removes the first list at 0" do
      subject = TasklistBlocks::Operations::RemoveTasklistBlock.new(position: 0)
      body = <<~MD
      # Markdown

      ```[tasklist]
      - [ ] foo
      - [ ] bar
      - [ ] baz
      ```

      ## Sub [tasklist]

      ```[tasklist]
      - [ ] foo
      - [ ] bar
      - [ ] baz
      ```
      MD
      result = subject.call(body)
      expected_result = <<~MD
      # Markdown


      ## Sub [tasklist]

      ```[tasklist]
      - [ ] foo
      - [ ] bar
      - [ ] baz
      ```
      MD
      assert_equal expected_result, result
    end

    test "removes the second list at 1" do
      subject = TasklistBlocks::Operations::RemoveTasklistBlock.new(position: 1)
      body = <<~MD
      # Markdown

      ```[tasklist]
      - [ ] foo
      - [ ] bar
      - [ ] baz
      ```

      ## Sub [tasklist]

      ```[tasklist]
      - [ ] foo
      - [ ] bar
      - [ ] baz
      ```

      ## Another [tasklist]

      ```[tasklist]
      - [ ] foo
      - [ ] bar
      - [ ] baz
      ```
      MD
      result = subject.call(body)
      expected_result = <<~MD
      # Markdown

      ```[tasklist]
      - [ ] foo
      - [ ] bar
      - [ ] baz
      ```

      ## Sub [tasklist]


      ## Another [tasklist]

      ```[tasklist]
      - [ ] foo
      - [ ] bar
      - [ ] baz
      ```
      MD
      assert_equal expected_result, result
    end

    test "handles titles" do
      subject = TasklistBlocks::Operations::RemoveTasklistBlock.new(position: 0)
      body = <<~MD
      # Markdown

      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] bar
      - [ ] baz
      ```

      ## Sub [tasklist]

      ```[tasklist]
      ### Sub Tasks
      - [ ] foo
      - [ ] bar
      - [ ] baz
      ```
      MD
      result = subject.call(body)
      expected = <<~MD
      # Markdown


      ## Sub [tasklist]

      ```[tasklist]
      ### Sub Tasks
      - [ ] foo
      - [ ] bar
      - [ ] baz
      ```
      MD
      assert_equal expected, result
    end

    test "handles multi-byte characters" do
      subject = TasklistBlocks::Operations::RemoveTasklistBlock.new(position: 0)
      text = "```[tasklist]\r\n- [ ] ☃\r\n- [ ] 😀\r\n```\r\n"
      result = subject.call(text)

      expected = ""
      assert_equal expected, result
    end

    test "handles abnormal breaks" do
      subject = TasklistBlocks::Operations::RemoveTasklistBlock.new(position: 0)
      text = "```[tasklist]\r- [ ] a\r- [ ] b\r```\r"
      result = subject.call(text)
      expected = ""
      assert_equal expected, result
    end
  end
end
