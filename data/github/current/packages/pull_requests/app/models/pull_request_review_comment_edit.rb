# typed: true
# frozen_string_literal: true

class PullRequestReviewCommentEdit < ApplicationRecord::Domain::IssuesPullRequests
  include FilterPipelineHelper
  include Instrumentation::Model
  include UserContentEdit::Core

  belongs_to :pull_request_review_comment

  alias_attribute :user_content_id, :pull_request_review_comment_id
  def user_content
    pull_request_review_comment
  end

  def async_user_content
    async_pull_request_review_comment
  end

  before_create :set_repository_id # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  def user_content_type
    "PullRequestReviewComment"
  end

  def global_id
    user_content_edit_id || "PullRequestReviewCommentEdit:#{id}"
  end

  private

  def set_repository_id
    self.repository_id = self.pull_request_review_comment&.repository_id
  end
end
