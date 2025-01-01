# typed: true
# frozen_string_literal: true

class ImportablePullRequestReviewThread < PullRequestReviewThread
  include Importable

  # rubocop:todo Rails/InverseOf
  belongs_to :pull_request_review, class_name: "ImportablePullRequestReview", foreign_key: :pull_request_review_id
  has_many :review_comments, class_name: "ImportablePullRequestReviewComment", foreign_key: :pull_request_review_thread_id
  # rubocop:enable Rails/InverseOf

  def type
    "PullRequestReviewThread"
  end
end
