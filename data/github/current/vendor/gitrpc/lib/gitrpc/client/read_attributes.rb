# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Read attributes for a set of paths and a given commit
    #
    # The attributes will be read from the tree the given commit
    # points to.
    #
    # commit_oid - String of commit OID
    # paths      - Array of Strings of file paths
    # keys       - Array of Strings of attribute keys to read
    #
    # Returns Hash with Strings of paths as keys and the corresponding
    # attributes hash as values.
    def read_attributes(commit_oid, paths, keys: nil, use_git: false)
      ensure_valid_full_oid(commit_oid)
      return {} if paths.empty?

      # Tree OID lookup necessary to (1) generate cache keys and
      # (2) reuse the object cache.
      commit_hash = read_commits([commit_oid]).first
      tree_oid = commit_hash["tree"]

      cache_keys = paths.map do |path|
        attributes_cache_key(tree_oid, path, keys)
      end

      cached_attributes = cache_get_multi(cache_keys, backend_method: :read_attributes)
      cached_paths = cached_attributes.values.map { |path, _| path }
      missing_paths = paths - cached_paths

      if missing_paths.any?
        all_attributes = send_message(:read_attributes, tree_oid, missing_paths, keys)
        missing_paths.zip(all_attributes).each do |path, attributes|
          key = attributes_cache_key(tree_oid, path, keys)
          value = [path, attributes]
          cached_attributes[key] = value
          @cache.set(key, value)
        end
      end

      paths_and_attributes = cached_attributes.values
      paths_and_attributes.each_with_object({}) do |(path, attributes), result|
        result[path] = attributes
      end
    end

    # Internal: Cache key for a given tree OID, path and set of keys
    #
    # Returns String
    def attributes_cache_key(tree_oid, path, keys)
      content_cache_key(
        "read_attributes", "v1", tree_oid,
        Digest::SHA256.hexdigest(path),
        Digest::SHA256.hexdigest(keys.join(":"))
      )
    end
  end
end
