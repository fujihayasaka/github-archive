# typed: true
# frozen_string_literal: true

require "test_helper"
require "securerandom"

class TasklistBlocks::Operations::ConvertToIssueTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @owner = create(:verified_user)
    @repo  = create(:repository, owner: @owner)
    @open_issue = create(:issue, repository: @repo, user: @owner)
  end

  setup do
    @issue_builder = Issue::Builder.new(@owner, @repo)
  end

  context "invalid input" do
    test "stats and does nothing when list is not found at position" do
      subject = klass.new(position: [1, 0], issue_builder: @issue_builder)
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
        tags: ["operation:ConvertToIssue", "status:failure", "reason:no_tasklist_block_found"]
      )
    end

    test "stats and does nothing when item is not found at position" do
      subject = klass.new(position: [0, 10], issue_builder: @issue_builder)
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
        tags: ["operation:ConvertToIssue", "status:failure", "reason:no_tasklist_item_found"]
      )
    end
  end

  context "valid input" do
    test "handles titles, replaces the draft with a new issue" do
      new_issue_title = SecureRandom.hex(10)
      subject = klass.new(position: [0, 0], issue_builder: @issue_builder)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] #{new_issue_title}
      - [ ] bar
      - [ ] baz
      ```
      MD
      result = subject.call(original)
      new_issue = Issue.find_by!(repository: @repo, title: new_issue_title)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] #{new_issue.url}
      - [ ] bar
      - [ ] baz
      ```
      MD
      assert_equal expected, result
    end

    test "works on non-zero, zero positions" do
      new_issue_title = SecureRandom.hex(10)
      subject = klass.new(position: [0, 2], issue_builder: @issue_builder)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] bar
      - [ ] #{new_issue_title}
      ```
      MD
      result = subject.call(original)
      new_issue = Issue.find_by!(repository: @repo, title: new_issue_title)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] bar
      - [ ] #{new_issue.url}
      ```
      MD
      assert_equal expected, result
    end

    test "handles multi-byte characters" do
      new_issue_title = "😒"
      subject = klass.new(position: [0, 1], issue_builder: @issue_builder)
      text = "```[tasklist]\r\n- [ ] ☃\r\n- [ ] #{new_issue_title}\r\n```\r\n"
      result = subject.call(text)
      new_issue = Issue.find_by!(repository: @repo, title: new_issue_title)
      expected = <<~MD
      ```[tasklist]
      - [ ] ☃
      - [ ] #{new_issue.url}
      ```
      MD
      assert_equal expected, result
    end

    test "handles abnormal breaks" do
      new_issue_title = SecureRandom.hex(10)
      subject = klass.new(position: [0, 1], issue_builder: @issue_builder)
      text = "```[tasklist]\r\n- [ ] a\r\n- [ ] #{new_issue_title}\r\n- [ ] c\r\n```\r\n"
      result = subject.call(text)
      new_issue = Issue.find_by!(repository: @repo, title: new_issue_title)
      expected = <<~MD
      ```[tasklist]
      - [ ] a
      - [ ] #{new_issue.url}
      - [ ] c
      ```
      MD
      assert_equal expected, result
    end

    test "handles abnormal leading spaces" do
      new_issue_title = SecureRandom.hex(10)
      subject = klass.new(position: [0, 0], issue_builder: @issue_builder)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ]               #{new_issue_title}
      - [ ] bar
      - [ ] baz
      ```
      MD
      result = subject.call(original)
      new_issue = Issue.find_by!(repository: @repo, title: new_issue_title)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] #{new_issue.url}
      - [ ] bar
      - [ ] baz
      ```
      MD
      assert_equal expected, result
    end

    test "handles abnormal trailing spaces" do
      new_issue_title = SecureRandom.hex(10)
      subject = klass.new(position: [0, 0], issue_builder: @issue_builder)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] #{new_issue_title + (" " * 10)}
      - [ ] bar
      - [ ] baz
      ```
      MD
      result = subject.call(original)
      new_issue = Issue.find_by!(repository: @repo, title: new_issue_title)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] #{new_issue.url}
      - [ ] bar
      - [ ] baz
      ```
      MD
      assert_equal expected, result
    end

    test "handles checked drafts" do
      new_issue_title = SecureRandom.hex(10)
      subject = klass.new(position: [0, 0], issue_builder: @issue_builder)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [x] #{new_issue_title}
      - [ ] foo
      ```
      MD
      result = subject.call(original)
      new_issue = Issue.find_by!(repository: @repo, title: new_issue_title)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [x] #{new_issue.url}
      - [ ] foo
      ```
      MD
      assert_equal expected, result
    end

    test "handles ignoring empty tasklist items when converting drafts" do
      new_issue_title = SecureRandom.hex(10)
      subject = klass.new(position: [0, 0], issue_builder: @issue_builder)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ]
      - [x] #{new_issue_title}
      - [ ] foo
      ```
      MD
      result = subject.call(original)
      new_issue = Issue.find_by!(repository: @repo, title: new_issue_title)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ]
      - [x] #{new_issue.url}
      - [ ] foo
      ```
      MD
      assert_equal expected, result
    end

    test "emits stat if issue in not saved" do
      subject = klass.new(position: [0, 0], issue_builder: @issue_builder)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ]
      - [ ] bar
      - [ ] baz
      ```
      MD
      Issue.any_instance.stubs(:valid?).returns(false) # stub issue validation failure
      subject.call(original)
      assert_dogstats_increment(
        1,
        "tasklist_blocks.operation",
        tags: ["operation:ConvertToIssue", "status:failure", "reason:could_not_save"]
      )
    end

    test "does not convert an issue URL" do
      subject = klass.new(position: [0, 0], issue_builder: @issue_builder)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] #{@open_issue.url}
      - [ ] bar
      - [ ] baz
      ```
      MD

      assert_difference("Issue.count", 0) do
        subject.call(original)
      end
      assert_dogstats_increment(
        1,
        "tasklist_blocks.operation",
        tags: ["operation:ConvertToIssue", "status:invalid"]
      )
    end

    test "handles non-dash item prefixes" do
      new_issue_title_1 = SecureRandom.hex(10)
      subject = klass.new(position: [0, 0], issue_builder: @issue_builder)
      text = "```[tasklist]\r\n* [ ] #{new_issue_title_1}\r\n```\r\n"
      result = subject.call(text)
      new_issue_1 = Issue.find_by!(repository: @repo, title: new_issue_title_1)
      expected = <<~MD
      ```[tasklist]
      * [ ] #{new_issue_1.url}
      ```
      MD
      assert_equal expected, result

      new_issue_title_2 = SecureRandom.hex(10)
      subject = klass.new(position: [0, 0], issue_builder: @issue_builder)
      text = "```[tasklist]\r\n1. [ ] #{new_issue_title_2}\r\n```\r\n"
      result = subject.call(text)
      new_issue_2 = Issue.find_by!(repository: @repo, title: new_issue_title_2)
      expected = <<~MD
      ```[tasklist]
      1. [ ] #{new_issue_2.url}
      ```
      MD
      assert_equal expected, result

      new_issue_title_3 = SecureRandom.hex(10)
      subject = klass.new(position: [0, 0], issue_builder: @issue_builder)
      text = "```[tasklist]\r\n+ [ ] #{new_issue_title_3}\r\n```\r\n"
      result = subject.call(text)
      new_issue_3 = Issue.find_by!(repository: @repo, title: new_issue_title_3)
      expected = <<~MD
      ```[tasklist]
      + [ ] #{new_issue_3.url}
      ```
      MD
      assert_equal expected, result
    end

    test "handles long titles" do
      long_issue_title = "#{SecureRandom.hex(80)} #{SecureRandom.hex(80)}"
      new_issue_title = SecureRandom.hex(10)
      subject = klass.new(position: [0, 1], issue_builder: @issue_builder)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] #{long_issue_title}
      - [ ] #{new_issue_title}
      - [ ] baz
      ```
      MD
      result = subject.call(original)
      new_issue = Issue.find_by!(repository: @repo, title: new_issue_title)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] #{long_issue_title}
      - [ ] #{new_issue.url}
      - [ ] baz
      ```
      MD
      assert_equal expected, result
    end

    test "handles drafts that only contains markdown formatting" do
      new_issue_title = "~#{SecureRandom.hex(10)}~"
      subject = klass.new(position: [0, 1], issue_builder: @issue_builder)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] #{new_issue_title}
      - [ ] bar
      ```
      MD
      result = subject.call(original)
      new_issue = Issue.find_by!(repository: @repo, title: new_issue_title)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] #{new_issue.url}
      - [ ] bar
      ```
      MD
      assert_equal expected, result
    end

    test "handles drafts that only contains markdown formatting and has other markdown in other draft items" do
      new_issue_title = "~#{SecureRandom.hex(10)}~"
      subject = klass.new(position: [0, 2], issue_builder: @issue_builder)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] ~biz~
      - [ ] #{new_issue_title}
      - [ ] bar
      ```
      MD
      result = subject.call(original)
      new_issue = Issue.find_by!(repository: @repo, title: new_issue_title)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] ~biz~
      - [ ] #{new_issue.url}
      - [ ] bar
      ```
      MD
      assert_equal expected, result
    end

    test "handles drafts that start with bold markdown formatting" do
      new_issue_title = "**#{SecureRandom.hex(10)}** foo"
      subject = klass.new(position: [0, 1], issue_builder: @issue_builder)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] #{new_issue_title}
      - [ ] biz
      ```
      MD
      result = subject.call(original)
      new_issue = Issue.find_by!(repository: @repo, title: new_issue_title)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] #{new_issue.url}
      - [ ] biz
      ```
      MD
      assert_equal expected, result
    end

    test "handles drafts that start with emphasis markdown formatting" do
      new_issue_title = "_#{SecureRandom.hex(10)}_ foo"
      subject = klass.new(position: [0, 2], issue_builder: @issue_builder)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] biz
      - [ ] #{new_issue_title}
      ```
      MD
      result = subject.call(original)
      new_issue = Issue.find_by!(repository: @repo, title: new_issue_title)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] biz
      - [ ] #{new_issue.url}
      ```
      MD
      assert_equal expected, result
    end

    test "handles drafts that have markdown formatting in the middle" do
      new_issue_title = "foo **#{SecureRandom.hex(10)}** bar"
      subject = klass.new(position: [0, 2], issue_builder: @issue_builder)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] bar
      - [ ] #{new_issue_title}
      ```
      MD
      result = subject.call(original)
      new_issue = Issue.find_by!(repository: @repo, title: new_issue_title)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] bar
      - [ ] #{new_issue.url}
      ```
      MD
      assert_equal expected, result
    end

    test "handles drafts that have markdown formatting at the end" do
      new_issue_title = "foo **#{SecureRandom.hex(10)}**r"
      subject = klass.new(position: [0, 1], issue_builder: @issue_builder)
      original = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] #{new_issue_title}
      - [ ] bar
      ```
      MD
      result = subject.call(original)
      new_issue = Issue.find_by!(repository: @repo, title: new_issue_title)
      expected = <<~MD
      ```[tasklist]
      ### Tasks
      - [ ] foo
      - [ ] #{new_issue.url}
      - [ ] bar
      ```
      MD
      assert_equal expected, result
    end
  end

  def klass
    TasklistBlocks::Operations::ConvertToIssue
  end
end
