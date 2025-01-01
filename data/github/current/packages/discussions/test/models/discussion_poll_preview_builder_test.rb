# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionPollPreviewBuilderTest < GitHub::TestCase
  context "#build" do
    test "creates poll preview with options" do
      question = "What is your favorite..?"
      options = %w[
        Pumpkin
        Red
      ]

      poll_preview = DiscussionPollPreviewBuilder.build(question: question, options: options)

      assert_equal poll_preview.question, question
      assert_equal poll_preview.options[0].option, "Pumpkin"
      assert_equal poll_preview.options[1].option, "Red"
    end
  end
end
