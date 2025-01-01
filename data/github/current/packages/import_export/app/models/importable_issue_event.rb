# typed: true
# frozen_string_literal: true

class ImportableIssueEvent < IssueEvent
  include Importable
  def type
    "IssueEvent"
  end
end
