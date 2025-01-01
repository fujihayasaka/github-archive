# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module Copilot
    class CodeReviewCommentFeedbackTest < GitHub::TestCase
      test "#text_response must be empty when feedback is positive" do
        feedback = create(:copilot_code_review_comment_feedback, :positive)
        assert_nil feedback.text_response
        assert_predicate(feedback, :valid?)

        feedback.text_response = "yo"
        refute_nil feedback.text_response
        refute_predicate(feedback, :valid?)
      end

      test "#text_response must be present when feedback is negative" do
        feedback = create(:copilot_code_review_comment_feedback, :negative)

        refute_nil feedback.text_response
        assert_predicate(feedback, :valid?)

        feedback.text_response = nil
        assert_nil feedback.text_response
        refute_predicate(feedback, :valid?)
      end

      test "#feedback_choices empty when feedback is positive" do
        feedback = create(:copilot_code_review_comment_feedback, :positive)
        assert_predicate(feedback, :valid?)
        assert_empty feedback.feedback_choices

        assert_raises(ActiveRecord::RecordInvalid) do
          create(:copilot_code_review_comment_feedback_choice, :unhelpful, code_review_comment_feedback: feedback)
        end
      end

      test "#feedback_choices populated when feedback is negative" do
        feedback = create(:copilot_code_review_comment_feedback, :negative)
        assert_predicate(feedback, :valid?)
        refute_empty feedback.feedback_choices

        feedback.feedback_choices.first.destroy!
        feedback.reload
        refute_predicate(feedback, :valid?)
        assert_empty feedback.feedback_choices
      end
    end
  end
end
