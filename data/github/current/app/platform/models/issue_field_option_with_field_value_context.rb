# typed: strict
# frozen_string_literal: true

# Marker wrapper: wraps an IssueFieldOption when accessed through a field value
# (e.g. IssueFieldMultiSelectValue#options). Signals to IssueFieldSingleSelectOption
# that auth should go through read_issue_field_values instead of read_issue_fields.
class Platform::Models::IssueFieldOptionWithFieldValueContext
  delegate_missing_to :@object

  sig { returns(IssueFieldOption) }
  attr_reader :object

  sig { returns(::IssueFieldValue) }
  attr_reader :field_value

  sig { params(object: IssueFieldOption, field_value: ::IssueFieldValue).void }
  def initialize(object, field_value:)
    @object      = object
    @field_value = field_value
  end
end
