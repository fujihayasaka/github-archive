# typed: true
# frozen_string_literal: true

class IssueCommentEdit < ApplicationRecord::Domain::IssuesPullRequests
  include FilterPipelineHelper
  include Instrumentation::Model
  include UserContentEdit::Core

  belongs_to :issue_comment

  alias_attribute :user_content_id, :issue_comment_id
  alias_attribute :diff, :compressed_diff

  attribute :compressed_diff, CompressedBinary.new(self.name, "diff")

  before_create :set_repository_id # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  def user_content
    issue_comment
  end

  def user_content_type
    "IssueComment"
  end

  def async_user_content
    async_issue_comment
  end

  def global_id
    user_content_edit_id || "IssueCommentEdit:#{id}"
  end

  private

  def set_repository_id
    self.repository_id = self.issue_comment&.repository_id
  end
end
