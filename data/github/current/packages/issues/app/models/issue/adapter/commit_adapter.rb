# typed: true
# frozen_string_literal: true

class Issue::Adapter::CommitAdapter < Issue::Adapter::Base
  TYPES = [
    PlatformTypes::Commit
  ].freeze

  attr_reader :abbreviated_oid, :repository, :resource_path

  def initialize(context, commit:)
    super(context)

    url = commit.path
    @resource_path = resource_path_for(url)

    @abbreviated_oid = commit.abbreviated_oid

    # It is possible that the commit source repository is outside of the issues repository
    @repository = if context.repository_adapter.id == commit.repository.id
      context.repository_adapter
    else
      Issue::Adapter::RepositoryAdapter.new(context, repository: commit.repository)
    end
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
