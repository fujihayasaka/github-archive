# typed: true
# frozen_string_literal: true

class ImportableIssueComment < IssueComment
  include Importable

  belongs_to :issue, class_name: "ImportableIssue", foreign_key: :issue_id # rubocop:todo Rails/InverseOf

  def synchronous_creation = true

  def type
    "IssueComment"
  end

  def body
    compressed_body
  end
end
