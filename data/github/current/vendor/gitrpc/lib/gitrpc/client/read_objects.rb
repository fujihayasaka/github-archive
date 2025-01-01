# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    include Scientist

    # Public: Retrieve commit information for a list of commit oids.
    #
    # oids - Array of hex object ID strings identifying commits.
    #
    # Returns an array with the same number of elements as oids where
    # the elements of the resulting array match up with the oids provided.
    #
    # Each element of the array is a hash with the following members:
    #
    #     { 'type'      => 'commit',
    #       'oid'       => string sha1,
    #       'tree'      => string sha1,
    #       'parents'   => [oid, ...],
    #       'author'    => [name, email, time],
    #       'committer' => [name, email, time],
    #       'message'   => string commit message,
    #       'encoding'  => string commit message encoding name }
    #
    # All keys are guaranteed to be present and non-nil. When a commit has
    # no parent commits, the parents array is present but empty.
    #
    # The author and committer values are simple three element tuple arrays.
    # All three elements are guaranteed to be present. The time element is an
    # ISO8601 formatted datetime string, not a Time object.
    #
    # Raises GitRPC::ObjectMissing when an object specified in oids
    # does not exist or can not be loaded from the object store.
    # Raises GitRPC::InvalidObject when the object is found but is not a
    # commit object.
    def read_commits(oids)
      read_objects(oids, "commit", false)
    end

    # Public: Retrieve blob information and content for a list of blob oids.
    #
    # oids - Array of hex object ID strings identifying blobs.
    #
    # Returns an array with the same number of elements as oids where
    # the elements of the resulting array match up with the oids provided.
    #
    # Each element of the array is a hash with the following members:
    #
    #     { 'type'      => 'blob',
    #       'oid'       => string sha1,
    #       'size'      => integer byte size of blob object,
    #       'data'      => string blob data,
    #       'encoding'  => string blob data character encoding,
    #       'binary'    => boolean indicating whether blob is binary or text,
    #       'truncated' => boolean indicating if data exceeded the size limit
    #                      and was truncated }
    #
    # All keys are guaranteed to be present and non-nil.
    #
    # Raises GitRPC::ObjectMissing when an object specified in oids
    # does not exist or can not be loaded from the object store.
    # Raises GitRPC::InvalidObject when the object is found but is not a
    # blob object.
    def read_blobs(oids)
      read_objects(oids, "blob")
    end

    # Public: Retreive blob info and non-truncated content for a blob oid.
    #
    # oids - hex object ID strings identifying a blob.
    #
    # Returns a hash with the following members:
    #
    #     { 'type'      => 'blob',
    #       'oid'       => string sha1,
    #       'size'      => integer byte size of blob object,
    #       'data'      => string blob data,
    #       'encoding'  => string blob data character encoding,
    #       'binary'    => boolean indicating whether blob is binary or text }
    #
    # All keys are guaranteed to be present and non-nil.
    #
    # Raises GitRPC::ObjectMissing when an object specified in oids
    # does not exist or can not be loaded from the object store.
    # Raises GitRPC::InvalidObject when the object is found but is not a
    # blob object.
    def read_full_blob(oid)
      ensure_valid_full_oid(oid)

      object = send_message(:read_full_blob, oid)
      GitRPC::Encoding.tag_compatible(object["data"], object["encoding"])
      object
    end

    # Public: The main git object reading interface. Reads commit, tree,
    # blob, and tag objects from cache and then the object store and presents as
    # simple hash data structures.
    #
    # This method is optimized for loading multiple objects using a single cache
    # lookup followed possibly by a single RPC call for tags that aren't in cache.
    #
    # oids - Array of hex object ID strings identifying objects.
    # type - Optional expected type to validate against as objects are
    #        loaded. Must be 'commit', 'tree', 'blob', or 'tag'. nil to disable.
    #
    # Returns an array with the same number of elements as oids where
    # the elements of the resulting array match up with the oids provided.
    #
    # Each element of the array is a hash with at least the following members
    #
    #     { 'type'        => 'commit' | 'tree' | 'blob' | 'tag',
    #       'oid'         => string sha1 of the object,
    #       ... }
    #
    # Additional fields are defined by each object type. See the appropriate
    # read method for documentation.
    #
    # Raises GitRPC::ObjectMissing when an object specified in oids
    # does not exist or can not be loaded from the object store.
    # Raises GitRPC::InvalidObject when the type argument was provided and
    # and object found is not of the given type.
    def read_objects(oids = [], type = nil, skip_bad = false)
      return [] if oids.empty?

      # load as many objects as we can from cache
      keys = oids.map do |oid|
        ensure_valid_full_oid(oid)
        object_key(oid)
      end

      objects = cache_get_multi(keys, backend_method: :read_objects) || {}
      # validate loaded objects are of the expected type
      validate_objects(objects, type, skip_bad) if type

      # build list of cache miss oids
      miss_oids = []
      keys.zip(oids).each do |key, oid|
        if objects[key].nil?
          miss_oids << oid
        end
      end

      # load missing objects from the backend and write to cache
      if miss_oids.any?
        objs = send_message(:read_objects, miss_oids, type, skip_bad, read_trailers: :regexp)
        objs.each do |object|
          key = object_key(object["oid"])
          objects[key] = object
          @cache.set(key, object)
        end
      end

      # maintain original order of objects
      keys.map do |key|
        object = objects[key]
        next unless object

        object
      end.compact
    rescue GitRPC::ObjectMissing => boom
      @cache.delete(object_key(boom.oid))
      raise
    end

    # Internal: Cache key used to keep a single object in memcache.
    #
    # oid - 40 char object id string.
    #
    # Returns a key suitable for use with memcache.
    def object_key(oid)
      parts = [
        oid,
        GitRPC::Backend.blob_maximum_data_size,
        GitRPC::Backend.blob_truncate_data_size,
        "v5",
      ]
      content_cache_key(*parts)
    end

    # Internal: helper method to validate that all objects in a collection
    # are of a specific type.
    #
    # objects - An array of object hashes
    # type    - The git object type name to validate against as a string. Must
    #           be 'commit', 'tree', 'blob', or 'tag'.
    #
    # Returns nothing. Raises a GitRPC::InvalidObject exception if an object
    # passes validation.
    def validate_objects(objects, type, skip_bad)
      type = type.to_s
      objects.reject! do |_, object|
        if object.nil?
          true
        elsif type && type == object["type"]
          false
        else
          if skip_bad
            true
          else
            raise GitRPC::InvalidObject, "Invalid object type #{object['type']}, expected #{type}"
          end
        end
      end
    end
  end
end
