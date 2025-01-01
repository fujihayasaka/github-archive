# typed: true
# frozen_string_literal: true

class Issue::Adapter::TransferRepositoryAdapter < Issue::Adapter::Base
  TYPES = [
    PlatformTypes::RepositoryNode
  ].freeze

  attr_reader :id
  attr_reader :name
  attr_reader :name_with_owner
  attr_reader :is_private
  attr_reader :description

  def initialize(context, repository:)
    super(context)

    viewer = context.viewer

    @repository = repository
    @name = repository.name

    @name_with_owner = repository.nwo
    @description = repository.description
    @id = repository.global_relay_id
    @is_private = repository.private?
  end

  def is_private?
    @is_private
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
