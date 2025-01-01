# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    include Scientist

    # Public: Retrieve commit information for a list of commit oids.
    #
    # oids - Array of 40 char oid strings identifying commits.
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
    # oids - Array of 40 char oid strings identifying blobs.
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
    # oids - 40 char oid strings identifying a blob.
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

    # Public: Retrieve tree information including a list of entries for a list
    # of tree oids.
    #
    # oids - Array of 40 char oid strings identifying trees.
    #
    # Returns an array with the same number of elements as oids where
    # the elements of the resulting array match up with the oids provided.
    #
    # Each element of the array is a hash with the following members:
    #
    #     { 'type'    => 'tree',
    #       'oid'     => string sha1,
    #       'entries' => { tree entries hash } }
    #
    # The tree entries hash includes one item for each tree entry. The key is the
    # name of the tree entry and values have the following members:
    #
    #     { 'type'   => string entry type - 'tree' or 'blob',
    #       'oid'    => string entry oid,
    #       'mode'   => integer file mode,
    #       'name'   => string file name }
    #
    # Raises GitRPC::ObjectMissing when an object specified in oids
    # does not exist or can not be loaded from the object store.
    # Raises GitRPC::InvalidObject when the object is found but is not a
    # tree object.
    def read_trees(oids)
      read_objects(oids, "tree")
    end

    # Public: Retrieve tag information for a list of tag oids. Note that
    # normal tags don't have objects - they simply point to a commit. The
    # oids specified in the list must only identify real tag objects.
    #
    # oids - Array of 40 char oid strings identifying tags.
    #
    # Returns an array with the same number of elements as oids where
    # the elements of the resulting array match up with the oids provided.
    #
    # Each element of the array is a hash with the following members:
    #
    #     { 'type'        => 'tag',
    #       'oid'         => string sha1 of the tag,
    #       'name'        => string tag name,
    #       'message'     => string tag message,
    #       'tagger'      => [name, email, time],
    #       'target'      => string destination object id }
    #
    # The target almost always points to a commit oid although tagging other
    # types of objects is possible.
    #
    # Raises GitRPC::ObjectMissing when an object specified in oids
    # does not exist or can not be loaded from the object store.
    # Raises GitRPC::InvalidObject when the object is found but is not a
    # tag object.
    def read_tags(oids)
      read_objects(oids, "tag")
    end

    # Public: The main git object reading interface. Reads commit, tree,
    # blob, and tag objects from cache and then the object store and presents as
    # simple hash data structures.
    #
    # This method is optimized for loading multiple objects using a single cache
    # lookup followed possibly by a single RPC call for tags that aren't in cache.
    #
    # oids - Array of 40 char oid strings identifying objects.
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

    # Public: Reads the object headers, including object size, without
    # loading the full objects.
    #
    # This method is optimized for loading multiple objects using a single cache
    # lookup followed possibly by a single RPC call for tags that aren't in cache.
    #
    # oids - Array of 40 char oid strings identifying objects.
    #
    # Returns an array with the same number of elements as oids where
    # the elements of the resulting array match up with the oids provided.
    #
    # Each element of the array is a hash with at least the following members
    #
    #     { 'type' => 'commit' | 'tree' | 'blob' | 'tag',
    #       'size' => length of the object,
    #     }
    #
    # Raises GitRPC::ObjectMissing when an object specified in oids
    # does not exist or can not be loaded from the object store.
    def read_object_headers(oids)
      return [] if oids.empty?

      # load as many headers as we can from cache
      keys = oids.map do |oid|
        ensure_valid_full_oid(oid)
        object_headers_key(oid)
      end

      object_headers = cache_get_multi(keys, backend_method: :read_object_headers) || {}

      # build list of cache miss oids
      miss_oids = []
      keys.zip(oids).each do |key, oid|
        miss_oids << oid if object_headers[key].nil?
      end

      # load missing headers from the backend and write to cache
      if miss_oids.any?
        headers = send_message(:read_object_headers, miss_oids)

        miss_oids.zip(headers).each do |oid, headers|
          key = object_headers_key(oid)
          object_headers[key] = headers
          @cache.set(key, headers)
        end
      end

      # maintain original order of headers
      keys.map { |key| object_headers[key] }.compact
    rescue GitRPC::ObjectMissing => boom
      @cache.delete(object_headers_key(boom.oid))
      raise
    end

    # Internal: Cache key used to keep object headers in memcache.
    #
    # oid - 40 char object id string.
    #
    # Returns a key suitable for use with memcache.
    def object_headers_key(oid)
      parts = [
        oid,
        "headers",
        "v1",
      ]
      content_cache_key(*parts)
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
