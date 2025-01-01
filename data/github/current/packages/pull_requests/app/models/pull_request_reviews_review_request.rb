# typed: true
# frozen_string_literal: true

class PullRequestReviewsReviewRequest < ApplicationRecord::Domain::IssuesPullRequests
  validates_presence_of :review_request, :pull_request_review

  belongs_to :review_request
  belongs_to :pull_request_review

  before_create :set_repository_id # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  private def set_repository_id
    self.repository_id = pull_request_review&.repository_id
  end
end
