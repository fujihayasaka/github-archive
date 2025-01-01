# typed: strict
# frozen_string_literal: true

class Platform::Models::IssueFieldWithIssueContext
  # Delegate all methods to the @object, which is an instance of IssueField
  delegate_missing_to :@object

  sig { returns(T.nilable(Issue)) }
  attr_reader :issue

  # Define the type of @object
  sig { returns(IssueField) }
  attr_reader :object

  sig { params(object: IssueField, issue: T.nilable(Issue)).void }
  def initialize(object, issue: nil)
    @issue = issue
    @object = object
  end
end
