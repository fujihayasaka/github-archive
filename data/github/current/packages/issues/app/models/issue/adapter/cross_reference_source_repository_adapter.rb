# typed: true
# frozen_string_literal: true

class Issue::Adapter::CrossReferenceSourceRepositoryAdapter < Issue::Adapter::Base
  attr_reader :is_private, :name_with_display_owner

  def initialize(context, repository_id:)
    super(context)
    repository = @context.repositories_by_id[repository_id]
    @is_private = repository.private?
    @name_with_display_owner = repository.name_with_display_owner
  end

  # app/views/issues/events/_cross_reference.html.erb
  def is_private?
    @is_private
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
