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
    end

    class StyledDirectiveLine < T::Struct
      const :type, String
      const :blobLineNumber, Integer
      const :text, String
      const :ast, T::Array[T.untyped]
      const :left, T.nilable(Integer)
      const :right, T.nilable(Integer)
    end

    class FileRendererBlobData < T::Struct
      const :identityUuid, String
      const :size, Integer
      const :type, String
      const :url, String
    end

    class RichDiff < T::Struct
      const :canToggleRichDiff, T::Boolean
      const :defaultToRichDiff, T::Boolean
      const :proseDifffHtml, T.nilable(String)
      const :renderInfo, T.nilable(FileRendererBlobData)
      const :dependencyDiffPath, T.nilable(String)
    end

    class Entry < T::Struct
      const :isBinary, T::Boolean
      const :isSubmodule, T::Boolean
      const :isTooBig, T::Boolean
      const :diffLines, T::Array[DiffLine]
      const :linesAdded, T.nilable(Integer)
      const :linesChanged, T.nilable(Integer)
      const :linesDeleted, T.nilable(Integer)
      const :oldCommitOid, String
      const :newCommitOid, String
      const :oldTreeEntry, T.nilable(OldTreeEntry)
      const :newTreeEntry, T.nilable(NewTreeEntry)
      const :path, String
      const :pathDigest, String
      const :richDiff, T.nilable(RichDiff)
      const :status, String
      const :truncatedReason, T.nilable(String) # is this nilable?
      const :size, String
      const :reviewed, T::Boolean
    end

    sig do
      params(contents_data: PullRequests::PageData::Diffs::Contents::Loader::Data).returns(T::Array[Entry])
    end
    def self.call(contents_data)
      new.call(contents_data)
    end

    sig do
      params(contents_data: PullRequests::PageData::Diffs::Contents::Loader::Data).returns(T::Array[Entry])
    end
    def call(contents_data)
      contents_data.diffs.map do |diff|
        new_tree_entry = NewTreeEntry.new(
          mode: diff.new_tree_entry&.mode.to_i,
          path: diff.new_tree_entry&.path,
          lineCount: diff.new_tree_entry&.line_count,
          isGenerated: diff.new_tree_entry&.generated?,
        ) if diff.new_tree_entry.present?

        old_tree_entry = OldTreeEntry.new(
          mode: diff.old_tree_entry&.mode.to_i,
          path: diff.old_tree_entry&.path,
          lineCount: diff.old_tree_entry&.line_count,
        ) if diff.old_tree_entry.present?

        Entry.new(
          isBinary: diff.diff_entry.binary?,
          isSubmodule: diff.diff_entry.submodule?,
          isTooBig: diff.diff_entry.too_big?,
          diffLines: diff.lines.map do |line| DiffLine.new(
            type: line.type,
            blobLineNumber: line.line_number,
            position: line.position,
            displayNoNewLineWarning: line.display_no_new_line_warning,
            text: line.text,
            html: line.html,
            left: line.left,
            right: line.right
          )
                     end,
          linesAdded: diff.diff_entry.additions,
          linesChanged: diff.diff_entry.changes,
          linesDeleted: diff.diff_entry.deletions,
          oldCommitOid: contents_data.before_commit_oid,
          newCommitOid: contents_data.after_commit_oid,
          newTreeEntry: new_tree_entry,
          oldTreeEntry: old_tree_entry,
          path: diff.diff_entry.path,
          pathDigest: Digest::SHA256.hexdigest(diff.diff_entry.path),
          status: diff.diff_entry.status_label&.upcase || "",
          truncatedReason: diff.diff_entry.truncated_reason,
          size: diff.binary_size ? number_to_human_size(diff.binary_size) : "",
          reviewed: diff.reviewed,
        )
      end
    end
  end
end
