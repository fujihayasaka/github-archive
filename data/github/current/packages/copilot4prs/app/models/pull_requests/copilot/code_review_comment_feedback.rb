# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    class CodeReviewCommentFeedback < ApplicationRecord::Domain::IssuesPullRequests
      self.table_name = "copilot_code_review_comment_feedbacks"
      self.strict_loading_by_default = true
      self.ignored_columns = %w[feedback_choice]

      include ::Repositories::BelongsToRepository
      belongs_to_repository_via_domain
      belongs_to :code_review_comment,
        class_name: "PullRequests::Copilot::CodeReviewComment",
        foreign_key: :copilot_code_review_comment_id,
        inverse_of: :user_feedbacks

      has_many :feedback_choices,
        class_name: "PullRequests::Copilot::CodeReviewCommentFeedbackChoice",
        foreign_key: :copilot_code_review_comment_feedback_id,
        inverse_of: :code_review_comment_feedback,
        dependent: :destroy

      # Corresponds to Hydro::Schemas::Copilot::Reviews::V0::Feedback::Type
      enum :feedback_type, {
        negative: -1,
        unknown: 0,
        positive: 1,
      }

      validates_presence_of :feedback_author_id
      validates_presence_of :feedback_type
      validates :feedback_choices, presence: true, if: :negative?
      validates :feedback_choices, absence: true, if: :positive?
      validates :text_response, presence: true, if: :negative?
      validates :text_response, absence: true, if: :positive?
    end
  end
end
