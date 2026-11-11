# typed: strict
# frozen_string_literal: true

class Platform::Models::IssueFieldWithRepoContext
  # Delegate all methods to the @object, which is an instance of IssueField
  delegate_missing_to :@object

  sig { returns(T.nilable(Integer)) }
  attr_reader :repository_id

  # Define the type of @object
  sig { returns(Issues::IIssueField) }
  attr_reader :object

  sig { params(object: Issues::IIssueField, repository_id: T.nilable(Integer)).void }
  def initialize(object, repository_id: nil)
    @repository_id = repository_id
    @object = object
  end
end
