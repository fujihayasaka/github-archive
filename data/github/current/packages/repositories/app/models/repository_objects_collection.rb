# typed: true
# frozen_string_literal: true

# This is the main interface for loading git objects from repositories. This
# includes Commit, Blob, Tree, and Tag object types. Objects may be read
# individually or in batch.
#
# This class is not usually instantiated directly by application code.
# Use the Repository#objects and Gist#objects accessors instead.
#
# Reading a single object:
#
#   >> repository.objects.read('deadbee...')
#   => #<Commit:deadbee...>
#
# Reading multiple objects efficiently:
#
#   >> repository.objects.read(['deadbee...', 'decafba...', ...])
#   => [#<Commit:deadbee...>, #<Tag:decafba..>, ...]
#
# All of the core git object models follow the same initialization pattern,
# taking a repository and generic object info hash. The object info hashes are
# documented under the gitrpc project. See the indivual models themselves or the
# gitrpc read_objects() call docs for more info:
#
# https://github.com/github/github/blob/master/vendor/gitrpc/doc/read_objects.md
class RepositoryObjectsCollection
  # The Repository object this collection is bound to.
  attr_reader :repository

  # Mapping of git object type names to model classes.
  OBJECT_TYPES = {
    "commit" => Commit,
    "blob"   => Blob,
    "tree"   => Tree,
    "tag"    => Tag,
  }

  # Public: Create a new RepositoryObjectsCollection for the given repository.
  #
  # repository - A Repository object, or anything that responds to #rpc and
  #              returns a GitRPC::Client object.
  #
  # This class typically isn't instantiated directly from calling code. Use
  # Repository#objects, Gist#objects, etc.
  def initialize(repository)
    @repository = repository
  end

  # Public: Read git objects by their SHA1 oid. Supports reading a single or
  # multiple objects in a single cache lookup and possibly single roundtrip with
  # the backend fs machine when the cache misses.
  #
  # oids - Array of oid strings identifying commit, tag, blob, or tree
  #        objects or a single string oid.
  # type - Optional verification type name string: 'commit', 'tag', 'blob',
  #        or 'tree'. When given, other objects cause a GitRPC::InvalidObject
  #        exception to be raised.
  #
  # Returns a samely ordered array of Commit, Tag, Blob, or Tree objects when an
  # array is given or a single object when a string is given.
  # Raises GitRPC::ObjectMissing when any object can not be found.
  # Raises GitRPC::InvalidObject when found but doesn't match the type requested.
  def read(oids, type = nil)
    if oids.is_a?(Array)
      read_all(oids, type)
    else
      read_one(oids, type)
    end
  end

  # Internal: Read multiple git objects.
  #
  # oids - Array of string oids.
  # type - Optional verification type name string.
  #
  # Returns an array of Commit, Tag, Blob, or Tree objects.
  def read_all(oids, type = nil, skip_bad: false)
    verify_oid_format(oids)
    repository.read_objects(
      oids, type, skip_bad, feature_flag: :repository_objects_collection_read_objects_spokes_api).
      map { |object| build(object) }
  end

  # Internal: Read a single git objects.
  #
  # oids - String oid identifying the object.
  # type - Optional verification type name string.
  #
  # Returns a Commit, Tag, Blob, or Tree object.
  def read_one(oid, type = nil)
    oids = verify_oid_format([oid])
    object = repository.rpc.read_objects(oids, type).first
    build(object)
  end

  # Public: Check if one or more git objects exist in the repository. This also
  # primes the local cache with the raw object data so it's okay to call this
  # method and then follow it with a call to #read(). No additional RPC calls
  # should be necessary.
  #
  # oids - Array of oid strings identifying commit, tag, blob, or tree
  #        objects or a single string oid.
  # type - Optional verification type name string.
  #
  # Returns true if all objects exist and are of the requested type, false otherwise.
  def exist?(oids, type = nil)
    oids = verify_oid_format(oids)
    repository.rpc.read_objects(oids, type)
    true
  rescue GitRPC::ObjectMissing, GitRPC::InvalidObject
    false
  end

  # Public: Instantiate a new object of the given type with the given attributes.
  #
  # info - Hash of object attributes. The 'type' attribute must be present and
  #        must be set to 'commit', 'blob', 'tree', or 'tag'.
  #
  # Returns a Commit, Blob, Tree, or Tag object.
  # Raises TypeError when the type class cannot be determined from the type string.
  def build(info)
    type = info["type"]
    if klass = OBJECT_TYPES[type.to_s]
      klass.new(repository, info)
    else
      raise TypeError, "Invalid git object type: #{type.inspect}"
    end
  end

  # Internal: Verify that the given oid strings are exactly 40 character SHA1s.
  #
  # oids - Array of oid strings to check for validness.
  #
  # Returns an oids array when all oids match.
  # Raises InvalidObjectId when oids includes malformed oids.
  #
  # TODO Push this down into gitrpc's read_objects().
  def verify_oid_format(oids)
    Array(oids).each { |oid|  verify_sha_format(oid, true) }
  end

  # Internal: Verify that the sha given is actually a hex string
  #
  # sha  - sha string to check
  # full - whether to check for a full SHA1 (40-character string)
  #        defaults to false
  #
  # Returns sha if acceptable
  # Raises InvalidObjectId when not acceptable
  def verify_sha_format(sha, full = false)
    bad   = !sha.is_a?(String) || sha =~ /[^a-fA-F0-9]/
    bad ||= sha.size != 40 if full

    raise InvalidObjectId, "Invalid git object oid: #{sha.inspect}" if bad

    sha
  end

  # Raised when an invalid Oid is passed to a method
  class InvalidObjectId < ArgumentError; end
end
