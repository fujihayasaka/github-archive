# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    class CodeReviewCommentFeedbackChoiceValidator < ActiveModel::Validator
      sig { params(record: CodeReviewCommentFeedbackChoice).void }
      def validate(record)
        record.errors.add :incorrect_feedback_type, "feedback_type must be negative" unless record.code_review_comment_feedback&.negative?
      end
    end
  end
end
