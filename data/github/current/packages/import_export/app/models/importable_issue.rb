# typed: true
# frozen_string_literal: true

class ImportableIssue < Issue
  include Importable

  # rubocop:todo Rails/InverseOf
  belongs_to :pull_request, class_name: "ImportablePullRequest", foreign_key: :pull_request_id
  has_many :comments, -> { order("issue_comments.id ASC").limit(Issue::COMMENT_LIMIT) }, class_name: "ImportableIssueComment", foreign_key: :issue_id
  # rubocop:enable Rails/InverseOf

  def type
    "Issue"
  end

  def body=(body)
    self.compressed_body = body
  end

  def execute_create_issue_orchestration
    super(synchronous: true)
  end
end
