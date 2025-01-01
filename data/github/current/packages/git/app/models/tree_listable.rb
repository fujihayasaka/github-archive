# typed: true
# frozen_string_literal: true

# Methods related to reading git trees and tree entries.
# This mostly deals with listing Tree and Blob objects objects.
module TreeListable
  extend T::Helpers
  requires_ancestor { FeatureFlag::IFeatureTarget }
  requires_ancestor { GH::Interfaces::GitRPC }
  requires_ancestor { GH::Interfaces::SpokesAPI }
  requires_ancestor { GH::Interfaces::DefaultBranch }
  requires_ancestor { GitRepository::SpokesAdapter }

  DEFAULT_LIMITS = { truncate: false, limit: 1.megabyte }

  # Fetch the tree entries for a tree referenced by a commitish and a path
  #
  # treeish - A string referencing either a commit sha or a tree sha.
  # path    - The path of the subtree to retrieve entries from.
  #
  # Returns three-element tuple with String tree oid, Array of tree entries, and
  # either:
  # - a Boolean value for whether entries were truncated (if 'needs_truncated_count' is false)
  # - an Integer number of entries that were truncated from the tree due to 'limit'
  def tree_entries(treeish, path, recursive: false, limit: 1000, simplify_paths: false, skip_size: true, needs_truncated_count: false)
    # First, validate the inputs
    GitRPC::Util.ensure_valid_full_oid(treeish)
    path_has_trailing_slash = path&.ends_with?("/")
    path = normalize_git_path(path)

    # Generate the cache key Use the GitRPC cache key generator to avoid the
    # "encoding fixer".
    cache_key = rpc.content_cache_key("tree_entries", "v1", treeish, sha256(path.to_s), limit)
    if recursive
      cache_key << ":recursive"
    elsif simplify_paths
      cache_key << ":simplified"
    end
    cache_key << ":needs_truncated_count" if needs_truncated_count

    result = GitHub.cache.fetch(cache_key) do
      # Resolve the tree
      tree_selectors = T.let([{ by_id: { id: treeish } }], T::Array[T::Hash[Symbol, T.untyped]])
      if path.present?
        tree_selectors << {
          by_treeish_and_path: {
            treeish: { oid: { id: treeish } },
            path: { name: path }
          }
        }
      else
        tree_selectors << { by_name: { name: "#{treeish}^{tree}" } }
      end

      base_treeish, resolved_tree = spokes_api.resolve_objects_by(tree_selectors).items.first(2)

      raise GitRPC::ObjectMissing, "object not found - no match for id (#{treeish})" if base_treeish.error.present?
      if ![:TYPE_COMMIT, :TYPE_TREE].include?(base_treeish.object.type) # TODO: handle tags if desired
        raise GitRPC::InvalidObject, "Invalid object type #{SpokesAPI::Util.object_type_to_str(base_treeish.object.type)}, expected commit or tree"
      end

      if path.present?
        raise GitRPC::NoSuchPath, "the path '#{path}' does not exist in the given tree" if resolved_tree.error.present?
        if resolved_tree.object.type != :TYPE_TREE
          if path_has_trailing_slash
            raise GitRPC::NoSuchPath, "the path '#{path}' exists but is not a tree"
          else
            raise GitRPC::InvalidObject, "Invalid type at path: #{path}, expected tree, got #{SpokesAPI::Util.object_type_to_str(resolved_tree.object.type)}"
          end
        end
      elsif resolved_tree.error.present?
        # This shouldn't happen - if base_treeish exists and is either a commit
        # or tree, the peeled tree should also exist.
        GitHub.logger.error(
          "unexpected missing tree in tree_entries",
          "tree_entries_spokes.base_treeish" => base_treeish.to_h,
          "tree_entries_spokes.resolved_tree" => resolved_tree.to_h
        )
        raise GitRPC::ObjectMissing, "object not found - no match for id (#{treeish})"
      end

      # Next, read the tree entries
      selector = if path.present?
        {
          treeish_and_path_selector: {
            treeish: { oid: { id: treeish } },
            path: { name: path + "/" } # add a trailing directory separator to ensure list_tree_entries reads tree content, not the tree itself
          }
        }
      else
        { treeish_selector: { treeish: { oid: { id: treeish } } } }
      end

      truncated_count = T.let(nil, T.nilable(Integer))
      tree_entries = []
      symlink_entries = []
      SpokesAPI::Client.paged_responses do |cursor|
        begin
          spokes_api.list_tree_entries_by(selector, recursive:, flatten_paths: simplify_paths, cursor:)
        rescue SpokesAPI::NotFound => e
          # This shouldn't happen because we resolve the tree before calling
          # ListTrees. If it does, log some useful metadata for debugging before
          # raising the error.
          GitHub.logger.error(
            "unexpected Spokes API error in tree_entries",
            :exception => e,
            "tree_entries_spokes.selector" => selector,
            "tree_entries_spokes.base_treeish" => base_treeish.to_h,
            "tree_entries_spokes.resolved_tree" => resolved_tree.to_h
          )
          raise GitRPC::ObjectMissing, "object not found - no match for id (#{treeish})"
        end
      end.each do |tree|
        tree.entries.each do |entry|
          next if path.present? && entry.path.name == path # skip the root tree

          if !truncated_count.nil? || (!limit.nil? && tree_entries.length >= limit)
            truncated_count = 0 if truncated_count.nil?
            truncated_count += 1
            needs_truncated_count ? next : break
          end

          args = { object: entry.object, path: entry.path.name, mode: entry.mode.mode }
          tree_entries << args
          if !recursive && simplify_paths
            path_elements = Pathname.new(entry.path.name).relative_path_from(path || "").each_filename
            if path_elements.count > 1 && path_elements.first != ".."
              args[:simplified_path] = entry.path.name
              args[:path] = Pathname.new(path || "").join(path_elements.first || "").to_s
            end
          end
          symlink_entries << args if SpokesAPI::Util.symlink?(entry.mode.mode)
        end
        break if !needs_truncated_count && truncated_count
      end

      # Resolve any symlinks by 1) reading the content of each symlink,
      # and 2) manually resolving the object at each symlink path.
      unless symlink_entries.empty?
        batch_size = SpokesAPI::Client::RESOLVE_OBJECT_BATCH_SIZE

        # Read the symlink paths
        valid_symlinks = []
        symlink_entries.map do |arg_map|
          {
            by_id: { id: arg_map[:object].oid.id },
            object_type: { type: :TYPE_BLOB }
          }
        end.each_slice(batch_size).map do |batch|
          spokes_api.read_objects_by(batch)
        end.each_with_index do |result, i|
          result.objects.each_with_index do |obj, j|
            idx = i * batch_size + j
            sym_path = build_symlink_path(symlink_entries[idx][:path], obj)
            next if sym_path.nil?

            symlink_entries[idx][:symlink_path] = sym_path
            valid_symlinks << symlink_entries[idx]
          end
        end

        # Resolve the symlinked object
        valid_symlinks.map do |arg_map|
          {
            by_treeish_and_path: {
              treeish: { oid: { id: treeish } },
              path: { name: arg_map[:symlink_path] }
            }
          }
        end.each_slice(batch_size).map do |batch|
          spokes_api.resolve_objects_by(batch)
        end.each_with_index do |result, i|
          result.items.each_with_index do |item, j|
            # TODO: we intentionally exclude symlinks to submodules, even
            # though we're able to resolve them, because downstream object
            # lookups assume any symlink we resolve exists in the repo.
            valid_symlinks[i * batch_size + j][:symlink_target] = item.object unless item.object&.type == :TYPE_COMMIT
          end
        end
      end

      # Convert the tree entry content to an array of hashes
      entries = tree_entries.map do |arg_map|
        TreeEntry.create_info(**arg_map, from_collection: true)
      end

      [resolved_tree.object.oid.id, entries, needs_truncated_count ? truncated_count : !!truncated_count]
    end

    [result[0], result[1].map { |entry| TreeEntry.new(self, entry) }, result[2]]
  rescue SpokesAPI::NotFound => e
    # If we get to this point with a "NotFound" error, the repo is missing.
    # Raise the equivalent GitRPC error.
    raise GitRPC::InvalidRepository, e.message
  end

  # Fetch a single TreeEntry from a path and a commit or tree
  #
  # oid  - A string referencing either a commit sha or a tree sha.
  # path - The path of the entry to fetch.
  #
  # Returns a TreeEntry
  # Raises GitRPC::NoSuchPath if no tree entry is found
  def tree_entry(oid, path, opts = {})
    opts = DEFAULT_LIMITS.merge(opts)

    # Expand options
    type = SpokesAPI::Util.str_to_object_type(opts[:type], strict: false)
    limit = opts.fetch(:limit, GitRPC::Backend::TREE_ENTRY_SIZE_LIMIT)
    truncate = opts.fetch(:truncate, GitRPC::Backend::TREE_ENTRY_TRUNCATE_LIMIT)

    # Validate/normalize inputs
    GitRPC::Util.ensure_valid_full_oid(oid)
    entry_name = SpokesAPI::Util.normalize_path(path) || ""
    path = normalize_git_path(path)

    cache_key = rpc.content_cache_key("tree_entry", "v1", oid, sha256(path), opts[:truncate], opts[:limit], opts[:type])
    entry = GitHub.cache.fetch(cache_key) do
      if path.present?
        # Read the object by path
        #
        # We're using a bit of a hack here - by setting a "blob" type constraint,
        # we still resolve the object regardless of the type, but we'll only
        # actually read the data if it's a blob.
        treeish, obj = spokes_api.read_objects_by([
          # HACK: this specifically should *not* be a blob, but setting that type
          # constraint allows us to resolve the base tree without also reading its
          # tree entries.
          { by_id: { id: oid }, object_type: { type: :TYPE_BLOB } },
          {
            by_treeish_and_path: {
                treeish: { oid: { id: oid } },
                path: { name: path }
            },
            object_type: { type: :TYPE_BLOB }
          }
        ]).objects.take(2)

        ok_errors = [:ERROR_REASON_TYPE_MISMATCH, :ERROR_REASON_TOO_LARGE, nil]
        raise GitRPC::ObjectMissing, "object not found - no match for id (#{oid})" unless ok_errors.include?(treeish.error_object&.error_reason)
        raise GitRPC::InvalidObject, "Invalid object type #{SpokesAPI::Util.object_type_to_str(treeish.object.type)}, expected commit or tree" unless [:TYPE_COMMIT, :TYPE_TREE].include?(treeish.object&.type) # TODO: handle tags if desired

        raise GitRPC::NoSuchPath, "the path '#{path}' does not exist in the given tree" unless ok_errors.include?(obj.error_object&.error_reason) || obj.object&.type == :TYPE_COMMIT # Submodules resolve with "not found" error
        raise GitRPC::NoSuchPath, "the path '#{path}' exists but is not a tree" if entry_name.ends_with?("/") && obj.object&.type != :TYPE_TREE
        raise GitRPC::InvalidObject, "Invalid type at path: #{path}, expected #{opts[:type]}, got #{SpokesAPI::Util.object_type_to_str(obj.object.type)}" if type && type != obj.object&.type

        # Construct the entry content (if needed)
        extra_args = {}
        content_hash = {}
        if obj.object&.type == :TYPE_BLOB
          content_hash.merge!({
            "truncated" => T.let(false, T::Boolean),
            "size_over_limit" => T.let(false, T::Boolean),
            "data" => ""
          })

          if (limit && obj.object.size > limit) || obj.error_object&.error_reason == :ERROR_REASON_TOO_LARGE
            content_hash["truncated"] = true
            content_hash["size_over_limit"] = true
          else
            # Read the object contents
            content = if obj.truncated && (!truncate || obj.blob_object.data.size < truncate)
              # If we truncated the tree entry but need more data, stream it.
              spokes_api.get_blob_contents_streaming(obj.object.oid.id).dup
            else
              obj.blob_object.data
            end

            # Truncate the contents, if needed
            content = if truncate && obj.object.size > truncate
              content_hash["truncated"] = true
              content[0, truncate]
            else
              content_hash["truncated"] = false
              content.dup
            end

            content_hash["data"] = content
            content_hash["encoding"] = GitRPC::Encoding.guess_and_tag(content)
            content_hash["binary"] = content_hash["encoding"].nil?

            if SpokesAPI::Util.symlink?(obj.object.mode) && (sym_path = build_symlink_path(path, obj)).present?
              # Resolve the target entry
              sym_obj = spokes_api.resolve_objects_by([{
                by_treeish_and_path: {
                  treeish: { oid: { id: oid } },
                  path: { name: sym_path }
                }
              }]).items.first

              # TODO: we intentionally exclude symlinks to submodules, even
              # though we're able to resolve them, because downstream object
              # lookups assume any symlink we resolve exists in the repo.
              extra_args[:symlink_path] = sym_path
              extra_args[:symlink_target] = sym_obj.object unless sym_obj.object&.type == :TYPE_COMMIT
            end
          end
        end

        ent = TreeEntry.create_info(object: obj.object, path: path || "", mode: obj.object&.mode, **extra_args).merge(content_hash)
      else
        # If we are, for some reason, specifying a non-tree type on the root tree,
        # fail before making the request.
        raise GitRPC::InvalidObject, "Invalid type at path: #{path}, expected #{opts[:type]}, got tree" if type && type != :TYPE_TREE

        # We're just resolving the root, so look up the tree with ResolveObjects
        treeish, tree = spokes_api.resolve_objects_by([
          { by_id: { id: oid } },
          { by_name: { name: "#{oid}^{tree}" } }
        ]).items.take(2)

        raise GitRPC::ObjectMissing, "object not found - no match for id (#{oid})" if treeish.error.present?
        raise GitRPC::InvalidObject, "Invalid object type #{SpokesAPI::Util.object_type_to_str(treeish.object.type)}, expected commit or tree" if tree.error.present?

        {
          "path" => "",
          "name" => "",
          "mode" => 0o40000,
          "type" => "tree",
          "oid"  => tree.object.oid.id,
          "size" => nil,
        }
      end
    end

    entry["name"] = entry_name
    entry["content"] = entry["data"]
    TreeEntry.new(self, entry)
  rescue SpokesAPI::NotFound => e
    # A "NotFound" error in these Spokes API calls means the repo is missing.
    # Raise the equivalent GitRPC error.
    raise GitRPC::InvalidRepository, e.message
  end

  private def build_symlink_path(base_path, obj)
    return nil if obj.truncated || obj.blob_object&.data.nil? # Can't resolve if object is missing or incomplete

    # FIXME: we trim whitespace from the symlink here to match legacy
    # GitRPC behavior, but this makes us unable to resolve target paths
    # that do actually end with whitespace.
    relative_sym_path = obj.blob_object.data.strip
    return nil if relative_sym_path.include?("\0") # Can't resolve a path containing an invalid byte

    # Resolve the target entry
    Pathname.new("/#{base_path}")
            .dirname
            .join(relative_sym_path)
            .cleanpath.to_s.sub(/\A\/+/, "")
  end

  # Fetch a blob by path at a commit
  #
  # Delegates to tree entry, but does some error handling if the TreeEntry
  # is not a blob.
  #
  # oid  - The oid of either a tree object or a commit object to search in
  # path - The path to find relative to the root tree
  #
  # Returns a TreeEntry (guaranteed to be a blob type)
  # Returns nil if no blob is found
  def blob(oid, path, limits = DEFAULT_LIMITS)
    tree_entry(oid, path, limits.merge(type: "blob"))
  rescue GitRPC::NoSuchPath
    nil
  end

  # Fetch a tree by path at a commit
  #
  # Delegates to tree entry, but does some error handling if the TreeEntry
  # is not a tree.
  #
  # oid  - The oid of either a tree object or a commit object to search in
  # path - The path to find relative to the root tree
  #
  # Returns a TreeEntry (guaranteed to be a tree type)
  # Returns nil if no tree is found
  def tree(oid, path)
    tree_entry(oid, path, type: "tree")
  rescue GitRPC::NoSuchPath
    nil
  end

  # Fetch a blob by oid
  #
  # oid - The oid of the blob to fetch
  #
  # Returns a Blob object
  def blob_by_oid(oid, full_blob: true)
    blob_hash = if full_blob
      rpc.read_full_blob(oid)
    else
      self.read_objects([oid], :blob).first
    end

    Blob.new(self, blob_hash)
  end

  # Fetch all blobs for referenced by a commitish and a path
  #
  # treeish - A string referencing either a commit sha or a tree sha.
  def blobs(treeish)
    tree_summary = rpc.read_tree_summary_recursive(treeish)
    tree_summary.map do |tree_entry|
      tree_entry["type"] = "blob"
      data = tree_entry.delete("content")
      tree_entry["data"] = data if data
      TreeEntry.new(self, tree_entry)
    end
  end

  # Create a Directory object for a specified oid and path.
  #
  # oid  - A String referencing either a commit sha or a tree sha
  # path - The path to the directory to retrieve. Defaults to the root directory.
  #
  # Returns a Directory object
  def directory(oid, path = nil)
    Directory.new(self, oid, path).tap do |dir|
      return nil unless dir.commit_sha
    end
  rescue GitHub::DGit::UnroutedError
    nil
  end

  # Create a Directory object at an oid and the root path.
  #
  # oid - A String referencing either a commit sha or a tree sha,
  #       defaults to the base branch. (Default: default_branch)
  #
  # Returns a Directory object
  def root_directory(ref: default_branch)
    directory(ref)
  end

  private

  # Normalize and validate a path within a Git tree for use with the Spokes API.
  def normalize_git_path(path)
    path = SpokesAPI::Util.normalize_path(path)&.gsub(/\/\z/, "") # trim trailing directory separators
    return if path.nil?

    # Explicitly block paths that start with "." or ".."
    first_component = Pathname.new(path).each_filename.first
    raise GitRPC::NoSuchPath, "the path '#{first_component}' does not exist in the given tree" if %w[. ..].include?(first_component)

    path
  end
end
