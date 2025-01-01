# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module Copilot
    class CodeReviewCommentFeedbackChoiceTest < GitHub::TestCase
      test "saves feedback choice" do
        feedback = create(:copilot_code_review_comment_feedback, :negative)
        feedback_choice = feedback.feedback_choices.first
        assert_predicate(feedback_choice, :valid?)
        assert feedback_choice.unhelpful?
      end

      test "prevents feedback choice on positive feedback" do
        feedback = create(:copilot_code_review_comment_feedback, :positive)
        assert_raises(ActiveRecord::RecordInvalid) do
          feedback.feedback_choices.create(choice: :unhelpful, repository: feedback.repository)
          feedback.save!
        end
      end
    end
  end
end
