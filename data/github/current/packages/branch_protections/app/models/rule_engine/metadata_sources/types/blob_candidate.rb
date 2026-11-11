# typed: strict
# frozen_string_literal: true

class RuleEngine::MetadataSources::Types::BlobCandidate

  sig { returns(T.nilable(String)) }
  attr_reader :oid

  sig { returns(T.nilable(String)) }
  attr_reader :commit_oid

  sig { returns(T.nilable(String)) }
  attr_reader :path

  sig { returns(T.nilable(Integer)) }
  attr_reader :size

  sig { returns(T.nilable(String)) }
  attr_reader :contents

  sig do
    params(
      oid: T.nilable(String),
      commit_oid: T.nilable(String),
      path: T.nilable(String),
      size: T.nilable(Integer),
      contents: T.nilable(String),
    )
    .void
  end
  def initialize(oid:, commit_oid:, path:, size:, contents:)
    @oid = oid
    @commit_oid = commit_oid
    @path = path
    @size = size
    @contents = contents
  end

  sig { params(blob: GitHub::Spokes::Proto::Blobs::V1::ReachableBlobItem, size: Integer).returns(RuleEngine::MetadataSources::Types::BlobCandidate) }
  def self.from_spokes(blob, size:)
    self.new(
      oid: blob.blob_oid&.id,
      commit_oid: blob.commit_oid&.id,
      path: blob.path&.name,
      size: size,
      contents: nil,
    )
  end

  sig { params(blob: GitHub::Spokes::Proto::Blobs::V1::PushedBlobItem).returns(RuleEngine::MetadataSources::Types::BlobCandidate) }
  def self.from_spokes_pushed_blob_item(blob)
    self.new(
      oid: blob.oid&.id,
      commit_oid: blob.commit_oid&.id,
      path: blob.path&.name,
      size: blob.size,
      contents: nil,
    )
  end
end
