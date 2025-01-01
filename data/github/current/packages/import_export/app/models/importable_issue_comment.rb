# typed: true
# frozen_string_literal: true

class ImportableIssueComment < IssueComment
  include Importable

  belongs_to :issue, class_name: "ImportableIssue", foreign_key: :issue_id # rubocop:todo Rails/InverseOf

  def type
    "IssueComment"
  end

  def body
    compressed_body
  end

  def execute_create_issue_comment_orchestration
    super(synchronous: synchronous_creation_enabled?)
  end

  private

  def synchronous_creation_enabled?
    GitHub.flipper[:octoshift_synchronous_creation].enabled?(issue&.owner)
  end
end
