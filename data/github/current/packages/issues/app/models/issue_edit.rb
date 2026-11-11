# typed: true
# frozen_string_literal: true

class IssueEdit < ApplicationRecord::Domain::IssuesPullRequests
  include GitHub::UTF8
  include GitHub::UserContent
  include FilterPipelineHelper
  include Instrumentation::Model
  include UserContentEdit::Core

  belongs_to :issue

  alias_attribute :user_content_id, :issue_id

  validates :repository_id, presence: true, on: :create
  before_validation :set_repository_id, on: :create

  alias_attribute :diff, :compressed_diff

  attribute :compressed_diff, CompressedString.new(self.name, "diff")
  validates :compressed_diff, unicode: true, allow_blank: true, allow_nil: true

  def compressed_diff=(value)
    value = value.presence
    super
  end
  alias_method :diff=, :compressed_diff=

  def user_content
    issue
  end

  def async_user_content
    async_issue
  end

  def user_content_type
    "Issue"
  end

  def global_id
    user_content_edit_id || "IssueEdit:#{id}"
  end

  private def set_repository_id
    self.repository_id = T.must(issue).repository_id
  end
end
