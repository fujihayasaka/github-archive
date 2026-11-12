module SnapshotRequests
  module Provider
    class BlobOperationsProvider
      include DependencyGraph::Tracing
      # Git only tracks a few file modes, the rest are subdirs/links etc.
      # 100644 octal == non-executable file (blob)
      # 100755 octal == executable file (blob)
      BLOB_FILE_MODES = ["100644", "100755"].freeze

      def name
        raise NotImplementedError, "name needs to be implemented on the blob operations provider"
      end

      def get_tree(**args)
        raise NotImplementedError, "get_tree needs to be implemented on the blob operations provider"
      end

      def get_blob(**args)
        raise NotImplementedError, "get_blob needs to be implemented on the blob operations provider"
      end

      def resolve_objects(**args)
        raise NotImplementedError, "resolve_objects needs to be implemented on the blob operations provider"
      end

      trace_method :manifest_tree_entries_at_sha, span_attribute_extractor: -> (_instance, *args, **_kwargs) do
        {
          "gh.repo.id" => args.first,
          "gh.push.commit_sha" => args.second,
        }
      end
      # Public: Use Spokes to find Manifests at a certain SHA.
      #
      # Returns Array of BlobOperations::Responses::TreeEntry objects
      def manifest_tree_entries_at_sha(github_repository_id, sha)
        file_tree = get_tree(
          repository_id: github_repository_id,
          commit_id: sha
        ).tree_entries

        file_tree.keep_if do |tree_entry|
          # skip subdirectory or link entries in the tree, keep blobs w/manifest paths!
          BLOB_FILE_MODES.include?(tree_entry&.mode) &&
            ManifestAdapters.recognized_path?(path: tree_entry.path)
        end
      end
    end
  end
end
