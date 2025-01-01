# typed: strict
# frozen_string_literal: true

class Platform::Models::IssueTypeWithContext
  delegate_missing_to :@object

  sig { returns(T.nilable(Repository)) }
  attr_reader :repository

  sig { returns(T.nilable(Issue)) }
  attr_reader :issue

  # Define the type of @object
  sig { returns(IssueType) }
  attr_reader :object

  sig { params(object: IssueType, repository: T.nilable(Repository), issue: T.nilable(Issue)).void }
  def initialize(object, repository: nil, issue: nil)
    @repository = repository
    @issue = issue
    @object = object
  end

  sig { returns(Promise[T.nilable(::User)]) }
  def async_owner
    @object.async_owner
  end

  sig { returns(T::Boolean) }
  def enabled?
    @object.enabled?
  end

  sig { params(matrix: T::Hash[Symbol, T::Boolean]).returns(T::Boolean) }
  def readable?(matrix)
    @object.readable?(matrix)
  end
end
