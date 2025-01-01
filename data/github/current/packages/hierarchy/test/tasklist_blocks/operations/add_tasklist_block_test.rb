# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlocks::Operations::AddTasklistBlockTest < GitHub::TestCase
  include DogstatsTestHelpers

  context "input handling" do
    test "adds a tasklist at the top of an empty issue body" do
      subject = TasklistBlocks::Operations::AddTasklistBlock.new
      body = ""
      result = subject.call(body)
      expected_result = <<~MD
      ```[tasklist]
      ### Tasks
      ```
      MD
      assert_equal expected_result, result
    end

    test "adds a tasklist after existing markdown in an issue body" do
      subject = TasklistBlocks::Operations::AddTasklistBlock.new
      body = <<~MD
      # Markdown
      MD
      result = subject.call(body)
      expected_result = <<~MD
      # Markdown

      ```[tasklist]
      ### Tasks
      ```
      MD
      assert_equal expected_result, result
    end
  end
end
