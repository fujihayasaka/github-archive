# typed: strict
# frozen_string_literal: true

class CacheEntry
  sig { returns(Integer) }
  attr_accessor :id

  sig { returns(String) }
  attr_accessor :scope

  sig { returns(String) }
  attr_accessor :key

  sig { returns(String) }
  attr_accessor :version

  sig { returns(Integer) }
  attr_accessor :size

  sig { returns(T.nilable(Google::Protobuf::Timestamp)) }
  attr_accessor :created_at

  sig { returns(T.nilable(Google::Protobuf::Timestamp)) }
  attr_accessor :last_accessed_at

  # these aliases are to match the names of the fields for the launch twirp types
  alias :lastAccessed :last_accessed_at
  alias :created :created_at

  sig do
    params(
      id: Integer,
      scope: String,
      key: String,
      version: String,
      size: Integer,
      created_at: T.nilable(Google::Protobuf::Timestamp),
      last_accessed_at: T.nilable(Google::Protobuf::Timestamp)
    ).void
  end
  def initialize(id:, scope:, key:, version:, size:, created_at:, last_accessed_at:)
    @id = id
    @scope = scope
    @key = key
    @version = version
    @size = size
    @created_at = created_at
    @last_accessed_at = last_accessed_at
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
    return false unless other.is_a?(self.class)

    other.id == id &&
    other.scope == scope &&
    other.key == key &&
    other.version == version &&
    other.size == size &&
    other.created_at == created_at &&
    other.last_accessed_at == last_accessed_at
  end

  sig { returns(GitHub::Launch::Services::Artifactcache::CacheEntry) }
  def to_launch
    GitHub::Launch::Services::Artifactcache::CacheEntry.new(
      id:,
      scope:,
      key:,
      version:,
      size:,
      created:,
      lastAccessed:,
    )
  end

  sig { params(entry: GitHub::Launch::Services::Artifactcache::CacheEntry).returns(CacheEntry) }
  def self.from_launch(entry)
    new(
      id: entry.id,
      scope: entry.scope,
      key: entry.key,
      version: entry.version,
      size: entry.size,
      created_at: entry.created,
      last_accessed_at: entry.lastAccessed
    )
  end

  sig { returns(MonolithTwirp::ActionsResults::Core::V1::CacheEntry) }
  def to_results
    MonolithTwirp::ActionsResults::Core::V1::CacheEntry.new(
      id:,
      scope:,
      key:,
      version:,
      size:,
      created_at:,
      last_accessed_at:,
    )
  end

  sig { params(entry: MonolithTwirp::ActionsResults::Core::V1::CacheEntry).returns(CacheEntry) }
  def self.from_results(entry)
    new(
      id: entry.id,
      scope: entry.scope,
      key: entry.key,
      version: entry.version,
      size: entry.size,
      created_at: entry.created_at,
      last_accessed_at: entry.last_accessed_at
    )
  end
end
