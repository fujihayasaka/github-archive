# typed: true
# frozen_string_literal: true

# Git Blob object. Eventual home for all app-level blob related behavior.
#
# NOTE This is largely just a stub right now. The blob accessors are not
# fleshed out. RepositoryObjectsCollection relies on a model being available
# to represent git object data.
#
# Read blobs from the repository:
#
#     repository = Repository.with_name_with_owner("great/repo")
#     blob = repository.objects.read('deadbee...')
#
# The blob's info hash hash this structure:
#
#     { 'type'      => 'blob',
#       'oid'       => string sha1,
#       'size'      => integer byte size of blob object,
#       'data'      => string blob data,
#       'encoding'  => string blob data character encoding,
#       'binary'    => boolean indicating whether blob is binary or text,
#       'truncated' => boolean indicating whether blob exceeded a max size }
#
# Only the oid is exposed as an attribute currently.
class Blob
  include Linguist::BlobHelper
  include GitHub::Relay::GlobalIdentification

  # The repository this blob belongs to.
  attr_reader :repository

  # The Blob's git object id. 40 character SHA1 strings only.
  attr_reader :info

  # Backend-detected encoding which matches raw_data
  attr_reader :raw_encoding

  # Create a new Blob.
  #
  # repository - The owning Repository object.
  # info       - Hash of blob attributes.
  #
  def initialize(repository, info = {})
    @repository = repository
    @info = info
    @raw_encoding = info["encoding"]
  end

  def oid
    info["oid"]
  end

  def global_id
    "#{repository.id}:#{oid}"
  end

  def data
    @data ||= begin
      GitHub::Encoding.guess_and_transcode(raw_data) || raw_data
    end
  end

  def raw_data
    info["data"]
  end

  def size
    info["size"]
  end

  # Blobs don't have a name, but legacy code elsewhere is
  # counting on this method existing so we'll just return nil
  def name
    nil
  end

  # Blobs don't have a mode, but legacy code elsewhere is
  # counting on this method existing so we'll just return nil
  def mode
    nil
  end

  # This is here to satisfy an interface implemented by all git object model
  # classes. The only interesting implementation is in Tag and Commit, since
  # there's no way to peel a blob to anything, let alone a commit.
  def peel_to_commit
    nil
  end

  def truncated?
    info["truncated"]
  end

  def binary?
    info["binary"]
  end

  def abbreviated_oid
    oid && oid[0, Commit::ABBREVIATED_OID_LENGTH]
  end

  # The Content-Type appropriate for the raw data in this blob
  def raw_content_type
    return "application/octet-stream" if binary?
    if raw_encoding
      "text/plain; charset=#{raw_encoding.downcase}"
    else
      "text/plain".freeze
    end
  end
end
