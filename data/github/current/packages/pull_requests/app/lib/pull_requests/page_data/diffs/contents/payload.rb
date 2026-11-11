# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Diffs::Contents
  class Payload
    include ActionView::Helpers::NumberHelper

    class NewTreeEntry < T::Struct
      const :mode, Integer
      const :path, String
      const :lineCount, Integer
      const :isGenerated, T::Boolean
    end

    class OldTreeEntry < T::Struct
      const :mode, Integer
      const :path, String
      const :lineCount, Integer
    end

    class DiffLine < T::Struct
      const :type, String
      const :blobLineNumber, Integer
      const :position, Integer
      const :displayNoNewLineWarning, T::Boolean
      const :text, String
      # can be plain text, plain HTML with intra-line changes, or syntax highlighted HTML
      const :html, String
      const :left, T.nilable(Integer)
      const :right, T.nilable(Integer)
      const :problems, T::Array[String] # e.g. ["ambiguousCharacters"]
    end

    class DiffEntry < T::Struct
      const :isBinary, T::Boolean
      const :isSubmodule, T::Boolean
      const :isTooBig, T::Boolean
      const :diffLines, T::Array[DiffLine]
      const :linesAdded, Integer
      const :linesChanged, Integer
      const :linesDeleted, Integer
      const :oldCommitOid, String
      const :newCommitOid, String
      const :oldTreeEntry, T.nilable(OldTreeEntry)
      const :newTreeEntry, T.nilable(NewTreeEntry)
      const :path, String
      const :pathDigest, String
      const :richDiff, T.nilable(PullRequests::PageData::Diffs::RichDiff::Payload::RichDiff)
      const :submodule, T.nilable(Diffs::PageData::Submodule::Payload::Payload)
      const :status, String
      const :truncatedReason, T.nilable(String)
      const :diffSize, String
      const :reviewed, T::Boolean
    end

    sig do
      params(contents_data: PullRequests::PageData::Diffs::Contents::Loader::Data).returns(T::Array[DiffEntry])
    end
    def self.call(contents_data)
      new.call(contents_data)
    end

    sig do
      params(contents_data: PullRequests::PageData::Diffs::Contents::Loader::Data).returns(T::Array[DiffEntry])
    end
    def call(contents_data)
      enable_diff_consolidation = contents_data.enable_diff_consolidation
      # First, create all diff entries without merging
      diff_entries = contents_data.diff_entries.map do |diff_entry|
        build_diff_entry(diff_entry, contents_data)
      end

      # Check if there are any duplicate paths
      paths = diff_entries.map(&:path)
      has_duplicates = paths.length != paths.uniq.length

      GitHub.dogstats.increment("pull_request.duplicate_paths.diff_contents", tags: ["has_duplicates:#{has_duplicates}"])

      # Only merge if duplicates exist
      if has_duplicates && enable_diff_consolidation
        merge_duplicate_entries(diff_entries)
      else
        diff_entries
      end
    end

    private

    sig do
      params(
        diff_entry: T.untyped,
        contents_data: PullRequests::PageData::Diffs::Contents::Loader::Data
      ).returns(DiffEntry)
    end
    def build_diff_entry(diff_entry, contents_data)
      new_tree_entry = NewTreeEntry.new(
        mode: diff_entry.new_tree_entry&.mode.to_i,
        path: diff_entry.new_tree_entry&.path,
        lineCount: diff_entry.new_tree_entry&.line_count || 0,
        isGenerated: diff_entry.new_tree_entry&.generated?,
      ) unless diff_entry.new_tree_entry.nil?

      old_tree_entry = OldTreeEntry.new(
        mode: diff_entry.old_tree_entry&.mode.to_i,
        path: diff_entry.old_tree_entry&.path,
        lineCount: diff_entry.old_tree_entry&.line_count || 0,
      ) unless diff_entry.old_tree_entry.nil?

      submodule = Diffs::PageData::Submodule::Payload.call(diff_entry.submodule) unless diff_entry.submodule.nil?

      DiffEntry.new(
        isBinary: diff_entry.is_binary,
        isSubmodule: diff_entry.is_submodule,
        isTooBig: diff_entry.is_too_big,
        diffLines: diff_entry.lines.map do |line|
          DiffLine.new(
            type: line.type,
            blobLineNumber: line.line_number,
            position: line.position,
            displayNoNewLineWarning: line.display_no_new_line_warning,
            text: line.text,
            html: line.html,
            left: line.left,
            right: line.right,
            problems: [line.has_added_ambiguous_characters ? "ambiguousCharacters" : nil].compact,
          )
        end,
        linesAdded: diff_entry.additions,
        linesChanged: diff_entry.changes,
        linesDeleted: diff_entry.deletions,
        oldCommitOid: contents_data.before_commit_oid,
        newCommitOid: contents_data.after_commit_oid,
        newTreeEntry: new_tree_entry,
        oldTreeEntry: old_tree_entry,
        path: diff_entry.path,
        pathDigest: Digest::SHA256.hexdigest(diff_entry.path),
        status: diff_entry.status_label.upcase,
        truncatedReason: diff_entry.truncated_reason,
        diffSize: diff_entry.binary_size ? number_to_human_size(diff_entry.binary_size) : "",
        reviewed: diff_entry.reviewed,
        richDiff: PullRequests::PageData::Diffs::RichDiff::Payload.call(diff_entry.rich_diff),
        submodule: submodule,
      )
    end

    sig { params(diff_entries: T::Array[DiffEntry]).returns(T::Array[DiffEntry]) }
    def merge_duplicate_entries(diff_entries)
      entries_map = T.let({}, T::Hash[String, DiffEntry])

      diff_entries.each do |diff_entry|
        existing = entries_map[diff_entry.path]

        if existing
          entries_map[diff_entry.path] = merge_entries(existing, diff_entry)
        else
          entries_map[diff_entry.path] = diff_entry
        end
      end

      entries_map.values
    end

    sig { params(existing: DiffEntry, current: DiffEntry).returns(DiffEntry) }
    def merge_entries(existing, current)
      merged_status = calculate_merged_status(existing.status, current.status)
      merged_diff_lines = merge_diff_lines(existing, current)

      DiffEntry.new(
        isBinary: existing.isBinary,
        isSubmodule: current.isSubmodule || existing.isSubmodule,
        isTooBig: existing.isTooBig,
        diffLines: merged_diff_lines,
        linesAdded: existing.linesAdded + current.linesAdded,
        linesChanged: existing.linesChanged + current.linesChanged,
        linesDeleted: existing.linesDeleted + current.linesDeleted,
        oldCommitOid: existing.oldCommitOid,
        newCommitOid: existing.newCommitOid,
        newTreeEntry: current.newTreeEntry || existing.newTreeEntry,
        oldTreeEntry: existing.oldTreeEntry || current.oldTreeEntry,
        path: existing.path,
        pathDigest: existing.pathDigest,
        status: merged_status,
        truncatedReason: existing.truncatedReason,
        diffSize: current.diffSize,
        reviewed: existing.reviewed,
        richDiff: current.richDiff || existing.richDiff,
        submodule: current.submodule || existing.submodule,
      )
    end

    sig { params(status1: String, status2: String).returns(String) }
    def calculate_merged_status(status1, status2)
      if (status1 == "REMOVED" && status2 == "ADDED") || (status1 == "ADDED" && status2 == "REMOVED")
        "CHANGED"
      else
        status1
      end
    end

    sig { params(existing: DiffEntry, current: DiffEntry).returns(T::Array[DiffLine]) }
    def merge_diff_lines(existing, current)
      # Ensure deletion lines come before addition lines
      if existing.status == "REMOVED" && current.status == "ADDED"
        existing.diffLines + current.diffLines
      elsif existing.status == "ADDED" && current.status == "REMOVED"
        current.diffLines + existing.diffLines
      else
        existing.diffLines + current.diffLines
      end
    end
  end
end
