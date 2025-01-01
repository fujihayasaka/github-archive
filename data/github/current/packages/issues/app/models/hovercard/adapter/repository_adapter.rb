# typed: true
# frozen_string_literal: true

class Hovercard::Adapter::RepositoryAdapter < Issue::Adapter::Base
  attr_reader :name
  attr_reader :name_with_display_owner
  attr_reader :owner

  attr_reader :tasklist_blocks_enabled
  attr_reader :resource_path

  def initialize(context, repository:)
    super(context)

    @name = repository.name
    @name_with_display_owner = repository.name_with_display_owner

    @owner = repository.owner
    @tasklist_blocks_enabled = repository.owner.feature_enabled?(:tasklist_block)
    @resource_path = resource_path_for(repository.path_uri)
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
