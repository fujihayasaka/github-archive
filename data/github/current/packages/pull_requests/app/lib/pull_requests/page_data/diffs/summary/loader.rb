# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Diffs::Summary
  class Loader
    class DiffSummary < T::Struct
      const :path, String
      const :old_path, String
      const :change_type, Diffs::Entry::ChangeType
      const :is_manifest_file, T::Boolean
      const :is_vendored, T::Boolean
      const :lines_added, Integer # for binary files we will default to 0
      const :lines_deleted, Integer # for binary files we will default to 0
      const :lines_changed, Integer # for binary files we will default to 0
      const :is_symlink, T::Boolean

      sig { returns(T::Boolean) }
      def vendored? = is_vendored
    end

    class Data < T::Struct
      const :summaries, T::Array[DiffSummary]
      const :enable_diff_consolidation, T::Boolean
    end

    class UnchangedFile
      AttributesType = T.type_alias { T::Hash[String, Object] }

      sig { params(repository: Repository, path: String).void }
      def initialize(repository, path:)
        @repository = repository
        @path = path
        @attributes = T.let(nil, T.nilable(AttributesType))
      end

      sig { returns(String) }
      attr_reader :path

      sig { params(commit_oid: String).returns(Promise[AttributesType]) }
      def async_attributes(commit_oid)
        Platform::Loaders::GitAttribute.load(@repository, @path.b, commit_oid).then do |attributes|
          @attributes = attributes
        end
      end

      sig { returns(T::Boolean) }
      def vendored?
        if @attributes.nil? || @attributes["linguist-vendored"].nil?
          # NOTE: We could also get this behaviour by including
          # `Linguist::BlobHelper` and calling `super` here, but a code comment
          # in that module recommends against including it in new places, and
          # it would come with a whole bunch of methods that wouldn't work
          # in this class.
          Linguist::BlobHelper::VendoredRegexp.match?(path)
        else
          @attributes["linguist-vendored"].to_s != "false"
        end
      end
    end

    sig do
      params(
        diff: GitHub::Diff,
        repository: Repository,
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        paths_with_markers: T::Array[String],
        current_user: T.nilable(User),
      ).returns(Data)
    end
    def self.load(diff:, repository:, limit_config:, paths_with_markers: [], current_user: nil)
      new(diff:, repository:, limit_config:, paths_with_markers:, current_user:).load
    end

    sig do
      params(
        diff: GitHub::Diff,
        repository: Repository,
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        paths_with_markers: T::Array[String],
        current_user: T.nilable(User),
      ).void
    end
    def initialize(diff:, repository:, limit_config:, paths_with_markers: [], current_user: nil)
      @diff = diff
      @repository = repository
      @limit_config = limit_config
      @paths_with_markers = paths_with_markers
      @current_user = T.let(current_user, T.nilable(User))
    end

    sig { returns(Data) }
    def load
      deltas = @limit_config.apply_files_page_limit(@diff) do
        @diff.summary.deltas
      end || [] # fallback to empty array for sorbet safety

      deltas_with_tree_entries = deltas.map { |delta| [delta, diff_delta_blob(delta)] }
      changed_file_attribute_promises = deltas_with_tree_entries.map do |_, tree_entry|
        tree_entry.async_attributes(@diff.sha2)
      end

      unchanged_paths = @paths_with_markers - deltas.flat_map(&:paths)
      unchanged_files = unchanged_paths.map do |path|
        UnchangedFile.new(@repository, path:)
      end
      unchanged_file_attribute_promises = unchanged_files.map do |file|
        file.async_attributes(@diff.sha2)
      end

      Promise.all(changed_file_attribute_promises + unchanged_file_attribute_promises).sync

      diff_summaries = deltas_with_tree_entries.map do |diff_delta, tree_entry|
        lines_added = diff_delta.additions || 0
        lines_deleted = diff_delta.deletions || 0
        is_symlink = tree_entry.mode == GitRPC::Diff::Delta::SYMLINK_MODE
        DiffSummary.new(
          path: diff_delta.path,
          old_path: diff_delta.old_file.path,
          change_type: Diffs::Entry::ChangeType.deserialize(
            diff_delta.status_label&.upcase
          ),
          is_manifest_file: DependencyManifestFile.recognized_path?(path: diff_delta.path),
          is_vendored: tree_entry.vendored?,
          lines_added: lines_added,
          lines_deleted: lines_deleted,
          lines_changed: lines_added + lines_deleted,
          is_symlink: is_symlink,
        )
      end

      diff_summaries += unchanged_files.map do |file|
        DiffSummary.new(
          path: file.path,
          old_path: file.path,
          change_type: Diffs::Entry::ChangeType::Unchanged,
          is_manifest_file: DependencyManifestFile.recognized_path?(path: file.path),
          is_vendored: file.vendored?,
          lines_added: 0,
          lines_deleted: 0,
          lines_changed: 0,
          # We use is_symlink for icon rendering, but we don't have the mode info here to determine.
          # unchanged files can be symlinks, but its okay if the unchanged icon renders instead.
          is_symlink: false,
        )
      end

      Data.new(
        summaries: diff_summaries.sort_by(&:path),
        enable_diff_consolidation: FeatureFlag.vexi.enabled?(:prx_diff_consolidation, @current_user, default: false)
      )
    end

    private

    sig do
      params(
        file: GitRPC::Diff::Delta::TreeNode,
      ).returns(TreeEntry)
    end
    def diff_delta_file_blob(file)
      TreeEntry.new(@repository, {
        "oid" => file.oid,
        "path" => file.path,
        "mode" => file.mode,
        "type" => "blob",
      })
    end

    sig do
      params(
        diff_delta: GitRPC::Diff::Delta,
      ).returns(TreeEntry)
    end
    def diff_delta_blob(diff_delta)
      if diff_delta.deleted?
        diff_delta_file_blob(diff_delta.old_file)
      else
        diff_delta_file_blob(diff_delta.new_file)
      end
    end
  end
end
