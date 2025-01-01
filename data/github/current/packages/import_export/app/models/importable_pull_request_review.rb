# typed: true
# frozen_string_literal: true

class ImportablePullRequestReview < PullRequestReview
  include Importable

  # rubocop:todo Rails/InverseOf
  has_many :review_comments, class_name: "ImportablePullRequestReviewComment", foreign_key: :pull_request_review_id
  has_many :review_threads, class_name: "ImportablePullRequestReviewThread", foreign_key: :pull_request_review_id
  # rubocop:enable Rails/InverseOf

  def self.workflow_spec
    PullRequestReview.workflow_spec
  end

  def self.workflow_column
    PullRequestReview.workflow_column
  end

  def type
    "PullRequestReview"
  end
end
