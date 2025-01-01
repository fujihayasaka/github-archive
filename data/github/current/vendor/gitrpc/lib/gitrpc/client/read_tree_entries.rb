# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Fetch a summary of a single tree in this Repository. The result
    # is an Array of blob Hashes containing the tree entry name, oid, size, etc.
    # The actual blob data is **not** returned by this method.
    #
    # tree_id - The 40 char sha1 oid of the tree (not a commit oid).
    # path    - String path to a subtree from the root of the tree. This
    #           must not start with a slash (/) and is always relative
    #           to the root of the repository.
    #
    # Returns an Array of Hashes:
    #
    #     { 'oid'   => 40 char sha1 oid of the entry,
    #       'name'  => filename (not including the path prefix),
    #       'size'  => the untruncated size of the blob, if the entry is a blob,
    #       'type'  => the type of the entry (usually tree or blob),
    #       'mode'  => the integer filemode of the entry }
    #
    def read_tree_entries(oid, path: nil, limit: 1000, simplify_paths: false, skip_size: false)
      ensure_valid_full_oid(oid)

      path = normalize_path(path)

      use_git = self.feature_enabled?(:read_tree_entries_git)

      cache_key = content_cache_key("read_tree_entries", use_git ? "v5" : "v4", oid, sha256(path.to_s), limit)
      cache_key << ":simplified" if simplify_paths
      cache_key << ":skip_size" if skip_size

      cache_fetch(cache_key, backend_method: :read_tree_entries) do
        if use_git
          perform_read_tree_entries(oid, path, limit, simplify_paths, skip_size, true)
        else
          science "read_tree_entries_git_experiment" do |e|
            e.context(
              {
                repository_key: self.repository_key,
                oid: oid, path: path,
                limit: limit,
                simplify_paths: simplify_paths,
                skip_size: skip_size
              }
            )
            e.use { perform_read_tree_entries(oid, path, limit, simplify_paths, skip_size, false) }
            e.try { perform_read_tree_entries(oid, path, limit, simplify_paths, skip_size, true) }
            e.compare_errors do |control, candidate|
              # Messages for the InvalidObject exception are not identical in both implementations

              # When asking for a path that does not exist, we should get a NoSuchPath at both cases, but the messages
              # are not guaranteed to be the same. The new implementation would need to perform additional computations
              # to return the same message as the old implementation, and the clients don't rely on the message.
              if (control.is_a? GitRPC::InvalidObject) && (candidate.is_a? GitRPC::InvalidObject) ||
                ((control.is_a? GitRPC::NoSuchPath) && (candidate.is_a? GitRPC::NoSuchPath))
                true
              else
                control.class == candidate.class && control.message == candidate.message
              end
            end
            e.run_if { !GitRPC::Client.disable_experiments? }
          end
        end
      end
    end

    def perform_read_tree_entries(oid, path, limit, simplify_paths, skip_size, use_git)
      endpoint = use_git ? :alternative_read_tree_entries : :read_tree_entries
      send_message(endpoint, oid, path, limit, simplify_paths, skip_size)
    end

    # Public: Recursively fetch a summary of a single tree in this Repository.
    # The result is an Array of blob Hashes containing the tree entry name,
    # oid, size, etc. The actual blob data is **not** returned by this method.
    #
    # tree_id - The 40 char sha1 oid of the tree or a commit containing one
    # path    - String path to a subtree from the root of the tree. This
    #           must not start with a slash (/) and is always relative
    #           to the root of the repository.
    #
    # Returns an Array of Hashes:
    #
    #     { 'oid'   => 40 char sha1 oid of the entry,
    #       'name'  => filename (not including the path prefix),
    #       'size'  => the untruncated size of the blob, if the entry is a blob,
    #       'type'  => the type of the entry (usually tree or blob),
    #       'mode'  => the integer filemode of the entry }
    #
    def read_tree_entries_recursive(oid, path = nil, limit = 1000)
      path = normalize_path(path)
      cache_key = content_cache_key("read_tree_entries_recursive:v4", oid, sha256(path.to_s), limit)

      cache_fetch(cache_key, backend_method: :read_tree_entries_recursive) do
        send_message(:read_tree_entries_recursive, oid, path, limit)
      end
    end

    # Public: read a single tree entry given a path and a sha.
    #
    # oid - the oid of the commit or tree to find the entry in.
    # path - The path of the blob or tree to look for.
    def read_tree_entry(oid, path = nil, options = {})
      ensure_valid_full_oid(oid)

      defaults = {
        "truncate" => GitRPC::Backend::TREE_ENTRY_TRUNCATE_LIMIT,
        "limit" => GitRPC::Backend::TREE_ENTRY_SIZE_LIMIT,
        "type" => nil
      }
      opts = defaults.merge(stringify_keys(options))

      path = normalize_path(path)
      key = "#{path}:#{opts["truncate"]}:#{opts["limit"]}:#{opts["type"]}"

      use_git = self.feature_enabled?(:read_tree_entry_git)

      if use_git
        perform_read_tree_entry(oid, key, path, opts, true)
      else
        science "read_tree_entry_git_experiment" do |e|
          e.context({ repository_key: self.repository_key, oid: oid, path: path })
          e.use { perform_read_tree_entry(oid, key, path, opts, false) }
          e.try { perform_read_tree_entry(oid, key, path, opts, true) }
          e.run_if { !GitRPC::Client.disable_experiments? }
          e.compare_errors do |control, candidate|
            # When asking for a path that does not exist, we should get a NoSuchPath at both cases, but the messages
            # are not guaranteed to be the same. The new implementation would need to perform additional computations
            # to return the same message as the old implementation, and the clients don't rely on the message.

            # GitRPC::Failure and the candidate is a GitRPC::InvalidObject is caused by a wrong type being passed
            # while tyring to raise a GitRPC::InvalidObject and makes Rugged to return a TypeError.
            # This is just here to satisfy the experiment, but no clients will be affected by this change.

            # There is an scenario where the control is a GitRPC::InvalidObject and the candidate is a GitRPC::NoSuchPath.
            # As an example, let's suppose that we have something like `dir/file.txt` and later we delete (and commit) the
            # file.txt file. If we ask for `dir`, the new implementation (cat-file) will return a NoSuchPath, while the
            # old implementation (Rugged) will return an InvalidObject.
            # This is just here to satisfy the experiment, but no clients will be affected by this change.
            if ((control.is_a? GitRPC::NoSuchPath) && (candidate.is_a? GitRPC::NoSuchPath)) ||
              ((control.is_a? GitRPC::Failure) && (candidate.is_a? GitRPC::InvalidObject)) ||
              ((control.is_a? GitRPC::InvalidObject) && (candidate.is_a? GitRPC::NoSuchPath))
              true
            else
              control.class == candidate.class && control.message == candidate.message
            end
          end
        end
      end
    end

    def perform_read_tree_entry(oid, key, path, opts, use_git)
      cache_key = content_cache_key("read_tree_entry:v4", oid, sha256(key), use_git)
      args = []
      endpoint = use_git ? :alternative_read_tree_entry : :read_tree_entry
      cache_fetch(cache_key, backend_method: :read_tree_entry) do
        send_message(endpoint, oid, path, opts).tap do |response|
          response["content"] = response["data"] # For legacy gist usage
          GitRPC::Encoding.tag_compatible(response["data"], response["encoding"])
        end
      end
    end
  end
end
