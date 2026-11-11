# typed: strict
# frozen_string_literal: true

class ArtifactTemplate
  sig { returns(String) }
  attr_reader :digest

  sig { returns(String) }
  attr_reader :name

  sig { returns(T.nilable(String)) }
  attr_reader :version

  sig { params(data: T::Hash[Symbol, T.untyped]).void }
  def initialize(data)
    digest = data[:digest]
    name = data[:name]
    version = data[:version].presence

    raise ArgumentError, "digest is required" if digest.blank?
    raise ArgumentError, "name is required" if name.blank?

    @digest = T.let(digest, String)
    @name = T.let(name, String)
    @version = T.let(version, T.nilable(String))
  end

  sig { returns(T::Hash[Symbol, String]) }
  def to_hash
    {
      digest: @digest,
      name: @name,
      version: @version,
    }
  end
end
