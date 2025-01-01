# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlocks::Operations::UpdateItemPositionTest < GitHub::TestCase
  include DogstatsTestHelpers

  context "invalid input" do
    test "returns nil when passed empty position arrays" do
      subject = klass.new(src: [], dst: [])
      assert_nil subject.call("```[tasklist]\n- [ ] a\n```\n")
    end

    test "returns nil when passed more than two position values" do
      subject = klass.new(src: [0, 1], dst: [0, 1, 1])
      assert_nil subject.call("```[tasklist]\n- [ ] a\n```\n")
    end

    test "returns nil when passed the same two position values" do
      subject = klass.new(src: [0, 1], dst: [0, 1])
      assert_nil subject.call("```[tasklist]\n- [ ] a\n```\n")
    end

    test "returns nil when passed negative values" do
      subject = klass.new(src: [0, 1], dst: [0, -1])
      assert_nil subject.call("```[tasklist]\n- [ ] a\n```\n")
    end

    test "stats and does nothing when list is not found at position" do
      subject = klass.new(src: [0, 0], dst: [1, 0])
      assert_nil subject.call("```[tasklist]\n- [ ] a\n```\n")

      assert_dogstats_increment(
        1,
        "tasklist_blocks.operation",
        tags: ["operation:UpdateItemPosition", "status:failure", "reason:no_destination_range"]
      )

      subject = klass.new(src: [1, 0], dst: [0, 0])
      assert_nil subject.call("```[tasklist]\n- [ ] a\n```\n")

      assert_dogstats_increment(
        1,
        "tasklist_blocks.operation",
        tags: ["operation:UpdateItemPosition", "status:failure", "reason:no_source_range"]
      )
    end
  end

  context "input handling" do
    test "handles titles" do
      subject = klass.new(src: [0, 0], dst: [0, 1])
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
      - [ ] bar
      - [ ] foo
      ```
      MD
      assert_equal expected, result
    end

    test "handles moving down" do
      subject = klass.new(src: [0, 0], dst: [0, 1])
      body = <<~MD
      # Markdown

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
      - [ ] bar
      - [ ] foo
      - [ ] baz
      ```
      MD
      assert_equal expected_result, result
    end

    test "handles moving up" do
      subject = klass.new(src: [0, 2], dst: [0, 1])
      body = <<~MD
      # Markdown

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
      - [ ] baz
      - [ ] bar
      ```
      MD
      assert_equal expected_result, result
    end

    test "handles moving up and positions correctly when there are empty items in tasklist" do
      subject = klass.new(src: [0, 2], dst: [0, 1])
      body = <<~MD
      # Markdown

      ```[tasklist]
      - [ ] foo
      - [ ]
      - [ ] baz
      - [ ] bar
      ```
      MD
      result = subject.call(body)
      expected_result = <<~MD
      # Markdown

      ```[tasklist]
      - [ ] foo
      - [ ]
      - [ ] bar
      - [ ] baz
      ```
      MD
      assert_equal expected_result, result
    end

    test "handles moving down and positions correctly when there are empty items in tasklist" do
      subject = klass.new(src: [0, 0], dst: [0, 2])
      body = <<~MD
      # Markdown

      ```[tasklist]
      - [ ] foo
      - [ ]
      - [ ] baz
      - [ ] bar
      ```
      MD
      result = subject.call(body)
      expected_result = <<~MD
      # Markdown

      ```[tasklist]
      - [ ]
      - [ ] baz
      - [ ] bar
      - [ ] foo
      ```
      MD
      assert_equal expected_result, result
    end

    test "handles moving down between lists" do
      subject = klass.new(src: [0, 0], dst: [1, 3])
      body = <<~MD
        # Markdown

        ```[tasklist]
        - [ ] foo
        - [ ] bar
        - [ ] baz
        ```

        ## Sub [tasklist]

        ```[tasklist]
        - [ ] first
        - [ ] second
        - [ ] third
        ```
      MD
      result = subject.call(body)
      expected_result = <<~MD
        # Markdown

        ```[tasklist]
        - [ ] bar
        - [ ] baz
        ```

        ## Sub [tasklist]

        ```[tasklist]
        - [ ] first
        - [ ] second
        - [ ] third
        - [ ] foo
        ```
      MD
      assert_equal expected_result, result
    end

    test "handles moving up between lists" do
      subject = klass.new(src: [1, 2], dst: [0, 1])
      body = <<~MD
        # Markdown

        ```[tasklist]
        - [ ] foo
        - [ ] bar
        - [ ] baz
        ```

        ## Sub [tasklist]

        ```[tasklist]
        - [ ] first
        - [ ] second
        - [ ] third
        ```
      MD
      result = subject.call(body)
      expected_result = <<~MD
        # Markdown

        ```[tasklist]
        - [ ] foo
        - [ ] third
        - [ ] bar
        - [ ] baz
        ```

        ## Sub [tasklist]

        ```[tasklist]
        - [ ] first
        - [ ] second
        ```
      MD
      assert_equal expected_result, result
    end

    test "handles multi-byte characters" do
      subject = klass.new(src: [0, 0], dst: [0, 1])
      body = <<~MD
        # Markdown

        ```[tasklist]
        - [ ] 😘
        - [ ] bar
        - [ ] baz
        ```
      MD
      result = subject.call(body)

      expected = <<~MD
        # Markdown

        ```[tasklist]
        - [ ] bar
        - [ ] 😘
        - [ ] baz
        ```
      MD
      assert_equal expected, result
    end

    test "handles long titles" do
      long_title = SecureRandom.hex(160)
      subject = klass.new(src: [0, 0], dst: [0, 1])
      body = <<~MD
        # Markdown

        ```[tasklist]
        - [ ] #{long_title}
        - [ ] bar
        ```
      MD
      result = subject.call(body)

      expected = <<~MD
        # Markdown

        ```[tasklist]
        - [ ] bar
        - [ ] #{long_title}
        ```
      MD
      assert_equal expected, result
    end

    test "handles return/newline characters" do
      subject = klass.new(src: [0, 1], dst: [0, 0])
      body = "\r\n```[tasklist]\r\n\r\n- [ ] a\r\n- [ ] b\r\n```"
      result = subject.call(body)

      expected = "\n```[tasklist]\n\n- [ ] b\n- [ ] a\n```"
      assert_equal expected, result
    end
  end

  private def klass
    TasklistBlocks::Operations::UpdateItemPosition
  end
end
