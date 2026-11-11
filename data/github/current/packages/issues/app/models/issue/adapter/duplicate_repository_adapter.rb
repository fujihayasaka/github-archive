# typed: true
# frozen_string_literal: true

class Issue::Adapter::DuplicateRepositoryAdapter < Issue::Adapter::Base
  attr_reader :name_with_display_owner

  def initialize(context, repository:)
    super(context)
    @name_with_display_owner = repository.name_with_display_owner
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
