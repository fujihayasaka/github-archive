# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    class CodeReviewCommentFeedbackChoice < ApplicationRecord::Domain::IssuesPullRequests
      include ActiveModel::Validations
      self.table_name = "copilot_code_review_comment_feedback_choices"
      self.strict_loading_by_default = true
      validates_with CodeReviewCommentFeedbackChoiceValidator

      belongs_to :repository
      belongs_to :code_review_comment_feedback,
        class_name: "PullRequests::Copilot::CodeReviewCommentFeedback",
        foreign_key: :copilot_code_review_comment_feedback_id,
        inverse_of: :feedback_choices

      # Corresponds to Hydro::Schemas::Copilot::Reviews::V0::RestrictedFeedback.Choice
      enum :choice, {
        unknown: 0,
        unhelpful: 1,
        incorrect: 2,
        not_true: 3,
        poorly_formatted: 4,
        offensive_or_discriminatory: 5,
        other: 6,
        suggestion_offensive_or_discriminatory: 7,
        suggestion_poorly_formatted: 8,
        suggestion_unhelpful: 9,
        suggestion_invalid: 10,
        incorrect_line: 11,
      }
    end
  end
end
