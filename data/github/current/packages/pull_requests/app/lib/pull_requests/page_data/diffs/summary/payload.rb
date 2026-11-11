# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Diffs::Summary
  class Payload
    class Summary < T::Struct
      const :changeType, Diffs::Entry::ChangeType
      const :isManifestFile, T::Boolean
      const :isVendored, T::Boolean
      const :path, String
      const :pathDigest, String
      const :linesAdded, Integer
      const :linesChanged, Integer
      const :linesDeleted, Integer
      const :isSymlink, T::Boolean
    end

    class Payload < T::Struct
      const :summaries, T::Array[Summary]
    end

    sig do
      params(summary_data: PullRequests::PageData::Diffs::Summary::Loader::Data).returns(Payload)
    end
    def self.call(summary_data)
      new.call(summary_data)
    end

    sig do
      params(summary_data: PullRequests::PageData::Diffs::Summary::Loader::Data).returns(Payload)
    end
    def call(summary_data)
      enable_diff_consolidation = summary_data.enable_diff_consolidation
      # First, create all summaries without merging
      summaries = summary_data.summaries.map do |diff_summary|
        Summary.new(
          changeType: diff_summary.change_type,
          isManifestFile: diff_summary.is_manifest_file,
          isVendored: diff_summary.vendored?,
          path: diff_summary.path,
          pathDigest: Digest::SHA256.hexdigest(diff_summary.path),
          linesAdded: diff_summary.lines_added,
          linesChanged: diff_summary.lines_changed,
          linesDeleted: diff_summary.lines_deleted,
          isSymlink: diff_summary.is_symlink,
        )
      end

      # Check if there are any duplicate paths
      paths = summaries.map(&:path)
      has_duplicates = paths.length != paths.uniq.length

      GitHub.dogstats.increment("pull_request.duplicate_entries.diff_summaries", tags: ["has_duplicates:#{has_duplicates}"])

      # Only merge if duplicates exist
      final_summaries = if has_duplicates && enable_diff_consolidation
        merge_duplicate_summaries(summaries)
      else
        summaries
      end

      Payload.new(
        summaries: final_summaries
      )
    end

    private

    sig { params(summaries: T::Array[Summary]).returns(T::Array[Summary]) }
    def merge_duplicate_summaries(summaries)
      summaries_map = T.let({}, T::Hash[String, Summary])

      summaries.each do |summary|
        existing = summaries_map[summary.path]

        if existing
          summaries_map[summary.path] = merge_summaries(existing, summary)
        else
          summaries_map[summary.path] = summary
        end
      end

      summaries_map.values
    end

    sig { params(existing: Summary, current: Summary).returns(Summary) }
    def merge_summaries(existing, current)
      merged_change_type = calculate_merged_change_type(existing.changeType, current.changeType)

      Summary.new(
        changeType: merged_change_type,
        isManifestFile: current.isManifestFile,
        isVendored: current.isVendored,
        path: existing.path,
        pathDigest: existing.pathDigest,
        linesAdded: existing.linesAdded + current.linesAdded,
        linesChanged: existing.linesChanged + current.linesChanged,
        linesDeleted: existing.linesDeleted + current.linesDeleted,
        isSymlink: existing.isSymlink || current.isSymlink
      )
    end

    sig { params(type1: Diffs::Entry::ChangeType, type2: Diffs::Entry::ChangeType).returns(Diffs::Entry::ChangeType) }
    def calculate_merged_change_type(type1, type2)
      if (type1 == Diffs::Entry::ChangeType::Removed && type2 == Diffs::Entry::ChangeType::Added) ||
         (type1 == Diffs::Entry::ChangeType::Added && type2 == Diffs::Entry::ChangeType::Removed)
        Diffs::Entry::ChangeType::Changed
      else
        type2
      end
    end
  end
end
