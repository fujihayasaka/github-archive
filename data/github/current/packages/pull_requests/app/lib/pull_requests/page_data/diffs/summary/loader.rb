# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Diffs::Summary
  class Loader
    class DiffSummary < T::Struct
      const :path, String
      const :change_type, Diffs::Entry::ChangeType
      const :is_manifest_file, T::Boolean
      const :is_vendored, T::Boolean
      const :lines_added, Integer # for binary files we will default to 0
      const :lines_deleted, Integer # for binary files we will default to 0
      const :lines_changed, Integer # for binary files we will default to 0

      sig { returns(T::Boolean) }
      def vendored? = is_vendored
    end

    class Data < T::Struct
      const :summaries, T::Array[DiffSummary]
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
      ).returns(Data)
    end
    def self.load(diff:, repository:, limit_config:, paths_with_markers: [])
      new(diff:, repository:, limit_config:, paths_with_markers:).load
    end

    sig do
      params(
        diff: GitHub::Diff,
        repository: Repository,
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        paths_with_markers: T::Array[String],
      ).void
    end
    def initialize(diff:, repository:, limit_config:, paths_with_markers: [])
      @diff = diff
      @repository = repository
      @limit_config = limit_config
      @paths_with_markers = paths_with_markers
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

      unchanged_paths = @paths_with_markers - deltas.map(&:path)
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
        DiffSummary.new(
          path: diff_delta.path,
          change_type: Diffs::Entry::ChangeType.deserialize(
            diff_delta.status_label&.upcase
          ),
          is_manifest_file: DependencyManifestFile.recognized_path?(path: diff_delta.path),
          is_vendored: tree_entry.vendored?,
          lines_added: lines_added,
          lines_deleted: lines_deleted,
          lines_changed: lines_added + lines_deleted,
        )
      end

      diff_summaries += unchanged_files.map do |file|
        DiffSummary.new(
          path: file.path,
          change_type: Diffs::Entry::ChangeType::Unchanged,
          is_manifest_file: DependencyManifestFile.recognized_path?(path: file.path),
          is_vendored: file.vendored?,
          lines_added: 0,
          lines_deleted: 0,
          lines_changed: 0,
        )
      end

      Data.new(
        summaries: diff_summaries.sort_by(&:path),
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
