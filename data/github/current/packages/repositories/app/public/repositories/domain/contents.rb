# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    class Contents < GH::Domain::Base

      DEFAULT_BRANCH_SELECTOR = T.let({ by_name: { name: "HEAD".b } }.freeze, T::Hash[Symbol, T::Hash[Symbol, String]])

      DEFAULT_BLOB_SIZE = T.let(1.megabyte, Integer)
      MAX_BLOB_SIZE = T.let(100.megabytes, Integer)
      SYMLINK_MODE = T.let(0o120000, Integer)
      FILE_MODE = T.let(0o100644, Integer)
      SUBMODULE_MODE = T.let(0o160000, Integer)

      MAX_TREE_ENTRIES = T.let(1_000, Integer)

      # Returns the metadata of a repository content by the given ref and path.
      # It will return the default branch content if the ref is not provided.
      # It will return the root directory content if the path is not provided.
      sig do
        params(
          repository: IRepository,
          ref: T.nilable(String),
          path: T.nilable(String)
        ).returns(Repositories::Contents::Metadata)
      end
      def metadata_by_ref_and_path(repository:, ref: nil, path: nil) # rubocop:disable Metrics/MethodLength
        repository = T.cast(repository, Repository) # rubocop:disable GitHub/AvoidCast
        # Paths like /folder/file.txt will become folder/file.txt
        # All the paths should be relative to the root of the repository.
        path = path.delete_prefix("/") if path.present?

        # Some paths can be whitespace only, so it's helpful to be able to use path.nil? checks everywhere
        path = nil if path == ""
        ref = repository.default_branch if ref.nil?

        if repository.feature_enabled?(:contents_metadata_with_cache)
          return contents_metadata_with_cache(repository, ref, path)
        end

        science "contents_metadata_with_cache" do |e|
          e.use do
            ref_selector_groups = Repositories::Contents::Selectors.build(repository:, ref:, path:)

            resolve_objects_by(repository:, ref_selector_groups:, path:)
          end
          e.try do
            contents_metadata_with_cache(repository, ref, path)
          end
          e.clean do |result|
            result&.to_h
          end
        end
      end

      # Returns a blob specified by the given path and Metadata.
      # Only returns blobs less than 100mb, which is the maximum size accepted by GitHub.
      sig { params(repository: IRepository, path: String, metadata: Repositories::Contents::Metadata, load_full_content: T::Boolean).returns(T.nilable(Repositories::Contents::Blob)) }
      def blob_by_path_and_metadata(repository:, path:, metadata:, load_full_content: false) # rubocop:disable Metrics/MethodLength
        return nil unless metadata.blob? &&
          (mode = metadata.path_object_mode) &&
          (oid = metadata.path_object_oid) &&
          (size = metadata.path_object_size) &&
          (commit_oid = metadata.ref_commit_oid)

        repository = T.cast(repository, Repository) # rubocop:disable GitHub/AvoidCast

        if repository.feature_enabled?(:blob_contents_with_cache)
          return blob_contents_with_cache(
            repository:,
            commit_oid:,
            oid:,
            mode:,
            size:,
            path:,
            load_full_content:
          )
        end

        science "blob_by_path_and_metadata_with_cache" do |e|
          e.use do
            contents = ""
            symlink_target = nil

            # If the full content is requested and the blob is between 1-100mb, we'll stream its full contents from spokes.
            # Otherwise, we'll load blobs up to 1mb in size.
            # If the blob is just too large, the content is omitted.
            if load_full_content && size > DEFAULT_BLOB_SIZE && size <= MAX_BLOB_SIZE
              contents = repository.spokes_api.get_blob_contents_streaming(oid)
            elsif size <= DEFAULT_BLOB_SIZE
              begin
                contents = repository.spokes_api.get_blob_contents({
                    by_object_id_path: {
                      oid: { id: commit_oid },
                      path: { name: path },
                      symlink_resolution: { follow_symlinks: true, max_depth: 2 }
                  } }
                ).contents

                if mode == SYMLINK_MODE
                  symlink_target = Repositories::Contents::Blob.new(
                    oid:,
                    path:,
                    mode: FILE_MODE,
                    contents: contents,
                    size: contents.size,
                  )
                end
              rescue SpokesAPI::Error => e
                # If a symlink was unresolvable, or if spokes returned a commit instead of a blob for the path (this can happen due to a git bug, see https://github.com/github/github/pull/357188),
                # We'll load the blob by id without doing symlink resolution.
                if e.is_a?(SpokesAPI::NotFound) && mode == SYMLINK_MODE || e.message == "expected to find a blob, found a commit instead"
                  contents = repository.spokes_api.get_blob_contents(by_id: { id: oid }).contents
                else
                  raise
                end
              end
            end

            Repositories::Contents::Blob.new(oid:, path:, mode:, contents: symlink_target ? "" : contents, symlink_target:, size:)
          end
          e.try do
            blob_contents_with_cache(
              repository:,
              commit_oid:,
              oid:,
              mode:,
              size:,
              path:,
              load_full_content:
            )
          end
        end
      end

      # Return a list of tree entries for the given tree OID, attempting to resolve any symlinks.
      sig { params(repository: IRepository, tree_oid: String, root_tree_oid: T.nilable(String), path: T.nilable(String)).returns(T.nilable(T::Array[Repositories::Contents::TreeEntry])) }
      def tree_entries_by_oid(repository:, tree_oid:, root_tree_oid:, path: nil)
        repository = T.cast(repository, Repository) # rubocop:disable GitHub/AvoidCast
        entries = repository.spokes_api.list_tree_entries(tree_oid:).entries.first(MAX_TREE_ENTRIES)

        # Some tree entries might be symlinks, try and resolve them.
        resolved_symlink_entries = resolve_tree_entry_symlinks(
          repository:, root_tree_oid: root_tree_oid || tree_oid, path: path || "",
          spokes_tree_entries: entries.filter { |e| e.mode&.mode == SYMLINK_MODE }
        )

        entries.map do |entry|
          type = Repositories::Contents::ContentHelpers.git_contents_type(entry.object.type)

          Repositories::Contents::TreeEntry.new(
            type: type,
            oid: entry.object.oid.id,
            path: entry.path.name,
            name: File.basename(entry.path.name),
            mode: entry.mode.mode,
            size: entry.object.size,
            symlink_target: resolved_symlink_entries[entry.object.oid.id],
          )
        end
      rescue SpokesAPI::NotFound
        nil
      end

      # Return a list of tree entries for the given tree OID, attempting to resolve any symlinks.
      sig { params(repository: IRepository, metadata: Repositories::Contents::Metadata, path: T.nilable(String)).returns(T.nilable(T::Array[Repositories::Contents::TreeEntry])) }
      def tree_entries_by_metadata(repository:, metadata:, path: nil) # rubocop:disable Metrics/MethodLength
        repository = T.cast(repository, Repository) # rubocop:disable GitHub/AvoidCast

        ref_commit_oid = T.must(metadata.ref_commit_oid)
        root_tree_oid = metadata.root_tree_entry_oid
        tree_oid = T.must(metadata.path_object_oid)

        tree_entries_key = Digest::SHA256.hexdigest([ref_commit_oid, root_tree_oid, tree_oid, path || "/",].join(":"))
        cache_key = repository.rpc.content_cache_key("tree_entries_by_metadata", "v0", tree_entries_key)
        tree_entries = T.let(nil, T.nilable(T::Array[Repositories::Contents::TreeEntry]))
        tree_entries_data = cache_fetch(cache_key, method: :tree_entries_by_metadata) do
          begin
            entries = repository.spokes_api.list_tree_entries(tree_oid:).entries.first(MAX_TREE_ENTRIES)

            # Some tree entries might be symlinks, try and resolve them.
            resolved_symlink_entries = resolve_tree_entry_symlinks(
              repository:, root_tree_oid: root_tree_oid || tree_oid, path: path || "",
              spokes_tree_entries: entries.filter { |e| e.mode&.mode == SYMLINK_MODE }
            )

            submodule_entries_data = T.let({}, T::Hash[String, Repositories::Contents::Submodule])
            submodule_entry_paths = entries.select { |e| e.mode.mode == SUBMODULE_MODE }.map { |e| [path, e.path.name].compact.join("/") }
            if submodule_entry_paths.any?
              submodule_entries_data = Repositories.domain.contents.submodules_by_commit_and_paths(
                repository: repository,
                commit_oid: ref_commit_oid,
                paths: submodule_entry_paths
              ).index_by(&:oid)
            end

            tree_entries = entries.map do |entry|
              type = Repositories::Contents::ContentHelpers.git_contents_type(entry.object.type)

              submodule_data = submodule_entries_data[entry.object.oid.id]

              Repositories::Contents::TreeEntry.new(
                type: type,
                oid: entry.object.oid.id,
                path: entry.path.name,
                name: File.basename(entry.path.name),
                mode: entry.mode.mode,
                size: entry.object.size,
                symlink_target: resolved_symlink_entries[entry.object.oid.id],
                submodule_path: submodule_data&.path,
                submodule_url: submodule_data&.url,
                submodule_name: submodule_data&.name,
              )
            end

            tree_entries.map(&:to_h)
          rescue SpokesAPI::NotFound
            nil
          end
        end

        tree_entries || tree_entries_data.map do |entry|
          if entry[:symlink_target].present?
            entry[:symlink_target] = Repositories::Contents::TreeEntry.new(**entry[:symlink_target])
          end
          Repositories::Contents::TreeEntry.new(**entry)
        end
      end

      # Retrieves submodules for a given repository, treeish, and paths.
      sig do
        params(
          repository: IRepository,
          commit_oid: String,
          paths: T::Array[String]
        ).returns(T::Array[Repositories::Contents::Submodule])
      end
      def submodules_by_commit_and_paths(repository:, commit_oid:, paths: [])
        return [] if paths.empty?

        repository = T.cast(repository, Repository) # rubocop:disable GitHub/AvoidCast

        response = repository.spokes_api.read_submodules(treeish: { oid: { id: commit_oid } }, paths: paths)

        response.submodules.map do |submodule|
          Repositories::Contents::Submodule.new(
            oid: submodule.oid.id,
            path: submodule.path.name,
            name: submodule.name.present? ? submodule.name : nil,
            url: submodule.url.present? ? submodule.url : nil,
          )
        end
      end

      # Retrieve the commit date for a given commit OID.
      sig { params(repository: IRepository, oid: String).returns(Time) }
      def get_commit_date(repository:, oid:)
        repository = T.cast(repository, Repository) # rubocop:disable GitHub/AvoidCast

        cache_key = repository.rpc.content_cache_key("get_commit_date", "v0", oid)

        cache_fetch(cache_key, method: :get_commit_date) do
          spokes_commit = repository.spokes_api.list_commits_for_ids(oids: [oid,]).commits.first
          committed_at = spokes_commit.commit_content.committer.date

          GitRPC::Util.unixtime_to_time([committed_at.timestamp.seconds, committed_at.offset])
        end
      end

      private

      sig { params(repository: Repository, ref: String, path: T.nilable(String)).returns(Repositories::Contents::Metadata) }
      def contents_metadata_with_cache(repository, ref, path)
        ref_and_path_hash = Digest::SHA256.hexdigest([ref, path || "/"].join(":"))
        cache_key = repository.rpc.repository_reference_cache_key("metadata_by_ref_and_path", "v0", ref_and_path_hash)

        content_metadata = T.let(nil, T.nilable(Repositories::Contents::Metadata))
        content_metadata_hash = cache_fetch(cache_key, method: :metadata_by_ref_and_path) do
          ref_selector_groups = Repositories::Contents::Selectors.build(repository:, ref:, path:)

          content_metadata = resolve_objects_by(repository:, ref_selector_groups:, path:)

          content_metadata.to_h
        end

        content_metadata || Repositories::Contents::Metadata.new(**content_metadata_hash)
      end

      sig do
        params(
          repository: Repository,
          commit_oid: String,
          oid: String,
          mode: Integer,
          size: Integer,
          path: String,
          load_full_content: T::Boolean
        ).returns(Repositories::Contents::Blob)
      end
      def blob_contents_with_cache(repository:, commit_oid:, oid:, mode:, size:, path:, load_full_content:) # rubocop:disable Metrics/MethodLength
        content_key = Digest::SHA256.hexdigest([commit_oid, oid, mode, size, path, load_full_content].join(":"))
        cache_key = repository.rpc.content_cache_key("blob_by_path_and_metadata", "v0", content_key)
        blob_content = T.let(nil, T.nilable(Repositories::Contents::Blob))
        blob_content_data = cache_fetch(cache_key, method: :blob_by_path_and_metadata) do
          contents = ""
          symlink_target = nil

          # If the full content is requested and the blob is between 1-100mb, we'll stream its full contents from spokes.
          # Otherwise, we'll load blobs up to 1mb in size.
          # If the blob is just too large, the content is omitted.
          if load_full_content && size > DEFAULT_BLOB_SIZE && size <= MAX_BLOB_SIZE
            contents = repository.spokes_api.get_blob_contents_streaming(oid)
          elsif size <= DEFAULT_BLOB_SIZE
            begin
              contents = repository.spokes_api.get_blob_contents({
                  by_object_id_path: {
                    oid: { id: commit_oid },
                    path: { name: path },
                    symlink_resolution: { follow_symlinks: true, max_depth: 2 }
                } }
              ).contents

              if mode == SYMLINK_MODE
                symlink_target = Repositories::Contents::Blob.new(
                  oid:,
                  path:,
                  mode: FILE_MODE,
                  contents: contents,
                  size: contents.size,
                )
              end
            rescue SpokesAPI::Error => e
              # If a symlink was unresolvable, or if spokes returned a commit instead of a blob for the path (this can happen due to a git bug, see https://github.com/github/github/pull/357188),
              # We'll load the blob by id without doing symlink resolution.
              if e.is_a?(SpokesAPI::NotFound) && mode == SYMLINK_MODE || e.message == "expected to find a blob, found a commit instead"
                contents = repository.spokes_api.get_blob_contents(by_id: { id: oid }).contents
              else
                raise
              end
            end
          end

          blob_content = Repositories::Contents::Blob.new(oid:, path:, mode:, contents: symlink_target ? "" : contents, symlink_target:, size:)

          blob_content.to_h
        end

        return blob_content unless blob_content.nil?

        if blob_content_data[:symlink_target].present?
          blob_content_data[:symlink_target] = Repositories::Contents::Blob.new(**blob_content_data[:symlink_target])
        end

        Repositories::Contents::Blob.new(**blob_content_data)
      end

      # Returns the metadata of a repository content by the given:
      # - ref_types: represents the ref types for which we will create the resolve object selectors.
      # - repository: the repository in which the content is located.
      # - ref: the ref in which it will try to resolve the content.
      # - path_string: the path if we want to resolve a specific file or directory. Otherwise, it will resolve the root directory content.
      sig do
        params(
          repository: Repository,
          ref_selector_groups: T::Array[Repositories::Contents::SelectorGroup],
          path: T.nilable(String)
        ).returns(Repositories::Contents::Metadata)
      end
      def resolve_objects_by(repository:, ref_selector_groups:, path:)
        # The resolved objects will be in the order of the selectors.
        # Each SelectorGroup contains some number of selectors, we flatten them all out to make a single spokes request.
        # To make easier the processing of the resolved objects, we will add the default branch repository selector at the beginning.
        selectors = [DEFAULT_BRANCH_SELECTOR] + ref_selector_groups.flat_map(&:selectors)

        resolved_objects = repository.spokes_api.resolve_objects_by(selectors).items.to_a

        # Since the DEFAULT_BRANCH_SELECTOR is the first selector
        # we can process it first.
        default_branch_resolved_item = resolved_objects.shift

        selected_group = process_resolved_objects(repository, ref_selector_groups, resolved_objects)

        build_metadata(
          repository:,
          head_resolved_item: default_branch_resolved_item,
          ref_selector_group: selected_group,
          path: path
        )
      end

      sig do
        params(
          repository: Repository,
          ref_selector_groups: T::Array[Repositories::Contents::SelectorGroup],
          resolved_objects: T::Array[GitHub::Spokes::Proto::Objects::V1::ResolveObjectsResponse::ResolvedItem]
        ).returns(Repositories::Contents::SelectorGroup)
      end
      def process_resolved_objects(repository, ref_selector_groups, resolved_objects)
        # resolved_objects is a flat array of spokes response objects corresponding to the provided selectors.
        # Iterate over this array and group the responses with the corresponding selector group.
        resolved_selector_groups = ref_selector_groups.map do |selector_group|
          selector_group.parse_resolved_objects(
            resolved_objects: resolved_objects.shift(selector_group.selectors.count),
            missing_path_fallback: -> (commit_oid, path) { try_resolve_tree_entry(repository, commit_oid, path) }
          )
          selector_group
        end

        # Find the first resolved object without error.
        selected_group = resolved_selector_groups.detect { |selector| selector.succeeded? }

        return selected_group if selected_group.present?

        # If all resolved objects have errors, we will return the last one.
        T.must(resolved_selector_groups.last)
      end

      # Returns the metadata of a repository content by the given resolved objects.
      sig do
        params(
          repository: Repository,
          head_resolved_item: GitHub::Spokes::Proto::Objects::V1::ResolveObjectsResponse::ResolvedItem,
          ref_selector_group: Repositories::Contents::SelectorGroup,
          path: T.nilable(String)
        ).returns(Repositories::Contents::Metadata)
      end
      def build_metadata(repository:, # rubocop:disable Metrics/MethodLength
        head_resolved_item:,
        ref_selector_group:,
        path: nil
      )

        ref_name = ref_selector_group.ref_name

        ref_commit_oid = ref_selector_group.commit_oid

        head_oid = nil
        if head_resolved_item.error.present?
          # It means the default branch does not exist.
          # However, if ref_commit_oid was found, it means the repository is not empty,
          # and we don't need the file server RT to ensure it is not empty.
          # Otherwise, we need to check if there aren't any other refs in the repository (`git show-ref`).
          if !ref_commit_oid && repository.empty_with_spokes?
            return Repositories::Contents::Metadata::EMPTY_REPOSITORY
          end
        else
          head_oid = T.must(T.must(head_resolved_item.object).oid).id
        end

        if ref_commit_oid.nil?
          return Repositories::Contents::Metadata.new(head_oid:)
        end

        if ref_selector_group.root_tree_entry_oid.nil?
          return Repositories::Contents::Metadata.new(
            head_oid:,
            ref_name:,
            ref_commit_oid:
          )
        end

        root_tree_entry_oid = ref_selector_group.root_tree_entry_oid

        if ref_selector_group.path_object_type.nil?
          if path.nil?
            # We are resolving the root directory
            return Repositories::Contents::Metadata.new(
              head_oid:,
              ref_name:,
              ref_commit_oid:,
              root_tree_entry_oid:,
              path_object_type: :tree,
              path_object_oid: root_tree_entry_oid,
              path_object_mode: ref_selector_group.path_object_mode,
              path_object_size: ref_selector_group.path_object_size
            )
          end
          return Repositories::Contents::Metadata.new(
            head_oid:,
            ref_name:,
            ref_commit_oid:,
            root_tree_entry_oid:
          )
        end

        Repositories::Contents::Metadata.new(
          head_oid:,
          ref_name:,
          ref_commit_oid:,
          root_tree_entry_oid:,
          path_object_type: ref_selector_group.path_object_type,
          path_object_oid: ref_selector_group.path_object_oid,
          path_object_mode: ref_selector_group.path_object_mode,
          path_object_size: ref_selector_group.path_object_size
        )
      end

      sig { params(repository: Repository, commit_oid: String, path: String).returns(T.nilable([Symbol, String, Integer, Integer])) }
      def try_resolve_tree_entry(repository, commit_oid, path)
        # bail if the path has any "..", "//", "./." etc in it
        return nil unless Pathname.new(path).cleanpath.to_s == path

        tree_entry = repository.spokes_api.list_tree_entries_by({ treeish_and_path_selector: { treeish: { oid: { id: commit_oid } }, path: { name: path } } }).entries.first
        return nil if tree_entry&.object.nil?

        [tree_entry.object.type, tree_entry.object.oid.id, tree_entry.mode.mode, tree_entry.object.size]
      rescue SpokesAPI::NotFound
        nil
      end

      sig { params(repository: Repository, root_tree_oid: String, path: String, spokes_tree_entries: T::Array[GitHub::Spokes::Proto::Types::V1::TreeEntry]).returns(T::Hash[String, Repositories::Contents::TreeEntry]) }
      def resolve_tree_entry_symlinks(repository:, root_tree_oid:, path:, spokes_tree_entries:) # rubocop:disable Metrics/MethodLength
        resolved_symlink_entries = {}
        symlink_entries = spokes_tree_entries.filter { |e| e.mode&.mode == SYMLINK_MODE }

        if symlink_entries.any?
          symlink_selectors = symlink_entries.map do |entry|
            { by_treeish_and_path: {
                treeish: { oid: { id: root_tree_oid } },
                path: { name: File.join(path, entry.path&.name) },
                symlink_resolution: { max_depth: 1 }
            } }
          end

          resolved_symlinks = repository.spokes_api.resolve_objects_by(symlink_selectors).items.to_a
          resolved_symlinks.each_with_index do |resolved, i|
            entry = symlink_entries[i] # The entry corresponding to the resolved symlink object.
            next unless entry && (entry_oid = entry.object&.oid&.id) && (entry_path = entry.path&.name)

            resolved_symlink_entries[entry_oid] = if resolved.error.present?
              # An error indicates we couldn't resolve the symlink.
              nil
            else
              Repositories::Contents::TreeEntry.new(
              type: Repositories::Contents::ContentHelpers.git_contents_type(resolved.object.type),
              oid: resolved.object.oid.id,
              path: entry_path,
              name: File.basename(entry_path),
              mode: resolved.object.mode,
              size: resolved.object.size,
            )
            end
          end
        end

        resolved_symlink_entries
      end

      sig { params(key: String, method: Symbol, block: T.proc.returns(T.untyped)).returns(T.untyped) }
      def cache_fetch(key, method:, &block)
        cache_result = "hit"
        GitHub.cache.fetch(key) do
          cache_result = "miss"
          block.call
        end
      ensure
        GitHub.dogstats.increment("cache_get.contents_domain", tags: ["method:#{method}", "result:#{cache_result}"])
      end
    end
  end
end
