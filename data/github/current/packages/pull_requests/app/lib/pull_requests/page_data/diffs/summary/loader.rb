# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Diffs::Summary
  class Loader
    class DiffSummary < T::Struct
      const :diff_delta, GitRPC::Diff::Delta
      const :tree_entry, TreeEntry
    end

    class Data < T::Struct
      const :summaries, T::Array[DiffSummary]
    end

    sig do
      params(
        diff: GitHub::Diff,
        repository: T.nilable(Repository),
      ).returns(Data)
    end
    def self.load(diff:, repository:)
      new(diff:, repository:).load
    end

    sig do
      params(
        diff: GitHub::Diff,
        repository: T.nilable(Repository)
      ).void
    end
    def initialize(diff:, repository:)
      @diff = diff
      @repository = repository
    end

    sig { returns(Data) }
    def load
      diff_summaries = @diff.summary.deltas.map do |diff_delta|
        DiffSummary.new(
          diff_delta: diff_delta,
          tree_entry: diff_delta_blob(diff_delta, @repository),
        )
      end

      TreeEntry.load_attributes!(diff_summaries.map(&:tree_entry), @diff.sha2)

      Data.new(
        summaries: diff_summaries,
      )
    end

    private

    sig do
      params(
        file: GitRPC::Diff::Delta::TreeNode,
        repository: T.nilable(Repository)
      ).returns(TreeEntry)
    end
    def diff_delta_file_blob(file, repository = nil)
      TreeEntry.new(repository, {
        "oid" => file.oid,
        "path" => file.path,
        "mode" => file.mode,
        "type" => "blob",
      })
    end

    sig do
      params(
        diff_delta: GitRPC::Diff::Delta,
        repository: T.nilable(Repository)
      ).returns(TreeEntry)
    end
    def diff_delta_blob(diff_delta, repository = nil)
      if diff_delta.deleted?
        diff_delta_file_blob(diff_delta.old_file, repository)
      else
        diff_delta_file_blob(diff_delta.new_file, repository)
      end
    end
  end
end
