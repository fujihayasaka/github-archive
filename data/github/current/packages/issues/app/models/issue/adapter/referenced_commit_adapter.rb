# typed: true
# frozen_string_literal: true

class Issue::Adapter::ReferencedCommitAdapter < Issue::Adapter::Base
  TYPES = [
    PlatformTypes::Commit
  ].freeze

  attr_reader :abbreviated_oid
  attr_reader :commit
  attr_reader :oid
  attr_reader :repository

  def initialize(context, commit:)
    super(context)

    @commit = commit
    @abbreviated_oid = commit.abbreviated_oid unless commit.nil?
    @repository = Issue::Adapter::RepositoryAdapter.new(@context, repository: commit.repository)
    @oid = commit.oid
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
