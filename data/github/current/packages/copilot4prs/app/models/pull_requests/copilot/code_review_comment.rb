# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    class CodeReviewComment < ApplicationRecord::Domain::IssuesPullRequests
      self.table_name = "copilot_code_review_comments"
      self.strict_loading_by_default = true

      belongs_to :repository
      belongs_to :subject, polymorphic: true
      belongs_to :copilot_coding_guideline, optional: true, class_name: "Copilot::CodingGuideline"

      has_many :user_feedbacks,
        class_name: "PullRequests::Copilot::CodeReviewCommentFeedback",
        foreign_key: :copilot_code_review_comment_id,
        inverse_of: :code_review_comment

      # Enforce that only subject types that belong to the issues-pull-requests domain are allowed
      ALLOWED_SUBJECT_TYPES = %w(PullRequestReviewComment).freeze
      validates :subject_type, inclusion: { in: ALLOWED_SUBJECT_TYPES }

      sig { returns(Integer) }
      def positive_feedback_count
        @positive_feedback_count ||= T.let(user_feedbacks.positive.count, T.nilable(Integer))
      end

      sig { returns(Integer) }
      def negative_feedback_count
        @negative_feedback_count ||= T.let(user_feedbacks.negative.count, T.nilable(Integer))
      end
    end
  end
end
