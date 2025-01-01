# typed: true
# frozen_string_literal: true

class PullRequestReviewEdit < ApplicationRecord::Domain::IssuesPullRequests
  include FilterPipelineHelper
  include Instrumentation::Model
  include UserContentEdit::Core

  belongs_to :pull_request_review

  before_validation :set_repository_id, on: :create
  validates :repository_id, presence: true, on: :create

  alias_attribute :user_content_id, :pull_request_review_id

  def user_content
    pull_request_review
  end

  def async_user_content
    async_pull_request_review
  end

  def user_content_type
    "PullRequestReview"
  end

  def global_id
    user_content_edit_id || "PullRequestReviewEdit:#{id}"
  end

  private def set_repository_id
    self.repository_id = pull_request_review&.repository_id
  end
end
