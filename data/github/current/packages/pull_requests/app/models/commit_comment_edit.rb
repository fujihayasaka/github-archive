# typed: true
# frozen_string_literal: true

class CommitCommentEdit < ApplicationRecord::Domain::IssuesPullRequests
  include FilterPipelineHelper
  include Instrumentation::Model
  include UserContentEdit::Core

  belongs_to :commit_comment

  alias_attribute :user_content_id, :commit_comment_id

  def user_content
    commit_comment
  end

  def async_user_content
    async_commit_comment
  end

  before_create :set_repository_id # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  def user_content_type
    "CommitComment"
  end

  def global_id
    user_content_edit_id || "CommitCommentEdit:#{id}"
  end

  private

  def set_repository_id
    self.repository_id = self.commit_comment&.repository_id
  end
end
