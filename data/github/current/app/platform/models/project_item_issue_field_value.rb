# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectItemIssueFieldValue < Platform::Models::ProjectItemFieldSpecialValue
  attr_reader :issue_field_value

  sig { params(issue_field_value: IssueFieldValue, item: MemexProjectItem, field: MemexProjectColumn).void }
  def initialize(issue_field_value, item, field)
    super(item, field)
    @issue_field_value = issue_field_value
    @platform_type_name = "ProjectV2ItemIssueFieldValue"
  end
end
