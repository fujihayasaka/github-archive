# typed: strict
# frozen_string_literal: true

class Platform::Models::IssueFieldWithRepoContext
  include Issues::IIssueField

  # Delegate any methods not listed below (e.g. AR helpers, global_relay_id) to
  # the wrapped field so callers don't notice the wrapper boundary.
  delegate_missing_to :@object

  sig { returns(T.nilable(Repository)) }
  attr_reader :repository

  sig { returns(T.nilable(Integer)) }
  attr_reader :repository_id

  # Define the type of @object
  sig { returns(Issues::IIssueField) }
  attr_reader :object

  sig { params(object: Issues::IIssueField, repository: T.nilable(Repository), repository_id: T.nilable(Integer)).void }
  def initialize(object, repository: nil, repository_id: nil)
    @repository = repository
    @repository_id = T.let(repository_id || repository&.id, T.nilable(Integer))
    @object = object
  end

  # Issues::IIssueField implementation — all delegated to the wrapped field.

  sig { override.returns(T.nilable(Integer)) }
  def id
    @object.id
  end

  sig { override.returns(T.nilable(Integer)) }
  def owner_id
    @object.owner_id
  end

  sig { override.returns(String) }
  def name
    @object.name
  end

  sig { override.returns(String) }
  def name_slug
    @object.name_slug
  end

  sig { override.returns(T.nilable(String)) }
  def description
    @object.description
  end

  sig { override.returns(User) }
  def owner
    @object.owner
  end

  sig { override.returns(String) }
  def data_type
    @object.data_type
  end

  sig { override.returns(String) }
  def visibility
    @object.visibility
  end

  sig { override.returns(T.nilable(Integer)) }
  def priority
    @object.priority
  end

  sig { override.returns(T::Hash[Symbol, T.untyped]) }
  def to_json_react
    @object.to_json_react
  end

  sig { override.returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def created_at
    @object.created_at
  end

  sig { override.params(viewer: T.nilable(User), repository_id: T.nilable(Integer)).returns(T::Boolean) }
  def viewable_by?(viewer:, repository_id: nil)
    @object.viewable_by?(viewer: viewer, repository_id: repository_id)
  end
end
