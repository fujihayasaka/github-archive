# typed: true
# frozen_string_literal: true

class ImportablePullRequestReviewComment < PullRequestReviewComment
  include Importable

  # rubocop:todo Rails/InverseOf
  belongs_to :pull_request_review, class_name: "ImportablePullRequestReview", foreign_key: :pull_request_review_id
  belongs_to :pull_request_review_thread,
    class_name: "ImportablePullRequestReviewThread",
    foreign_key: :pull_request_review_thread_id,
    autosave: true
  # rubocop:enable Rails/InverseOf

  def type
    "PullRequestReviewComment"
  end
end
