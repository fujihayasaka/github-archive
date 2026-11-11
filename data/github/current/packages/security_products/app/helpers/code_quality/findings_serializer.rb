# typed: strict
# frozen_string_literal: true

module CodeQuality
  module FindingsSerializer
    extend T::Helpers

    requires_ancestor { ApplicationController }

    include DiffLineChangeMarker
    include Commit::ReactDiffLinesHelper

    sig do
      params(
        findings: T::Enumerable[Turboquality::Proto::AiFileFindings],
        highlighted_diff: SyntaxHighlightedDiff,
      ).returns(
        T::Array[T::Hash[Symbol, T.untyped]]
      )
    end
    def serialized_ai_file_findings(findings, highlighted_diff)
      findings.map do |ff|
        {
          filePath: ff.file_path,
          lastPushAt: ff.pushed_at&.to_time&.utc&.iso8601,
          commitOid: ff.commit_oid,
          findings: ff.findings.map do |f|
            {
              message: f.message,
              startLine: f.start_line,
              startColumn: f.start_column,
              endLine: f.end_line,
              endColumn: f.end_column,
              fixFiles: f.suggested_fix_files.map do |sff|
                serialize_suggested_fix_file(
                  diff_content: sff.diff_content,
                  file_path: sff.file_path,
                  highlighted_diff: highlighted_diff,
                  include_raw_diff: true
                )
              end,
            }
          end,
        }
      end
    end

    sig do
      params(
        diff_content: T.nilable(String),
        file_path: T.nilable(String),
        highlighted_diff: SyntaxHighlightedDiff,
        include_raw_diff: T::Boolean,
      ).returns(T::Hash[Symbol, T.untyped])
    end
    def serialize_suggested_fix_file(diff_content:, file_path:, highlighted_diff:, include_raw_diff:)
      entries = []
      parser = GitHub::Diff::Parser.new(diff_content)
      parser.each do |entry|
        entry = T.let(entry, GitHub::Diff::Entry)
        entries << entry
      end

      # Highlight all entries to make use of caching
      highlighted_diff.highlight!(entries)
      diff_entries = []
      entries.each do |entry|
        entry = T.let(entry, GitHub::Diff::Entry)
        diff_entries << {
          linesAdded: entry.additions || 0,
          diffSize: "",
          linesChanged: entry.changes || 0,
          linesDeleted: entry.deletions || 0,
          isBinary: entry.binary?,
          isSubmodule: entry.submodule?,
          isTooBig: entry.too_big?,
          diffLines: serialize_diff_entry(entry, highlighted_diff),
          newTreeEntry: nil,
          oldTreeEntry: nil,
          path: entry.path,
          statusLabel: entry.status_label&.upcase || "",
          truncatedReason: entry.truncated_reason,
        }
      end

      result = {
        filePath: file_path,
        diffEntries: diff_entries,
      }
      result[:diff] = diff_content if include_raw_diff
      result
    end

    sig do
      params(
        diff_entry: GitHub::Diff::Entry,
        highlighted_diff: SyntaxHighlightedDiff,
      ).returns(T::Array[T::Hash[Symbol, T.untyped]])
    end
    def serialize_diff_entry(diff_entry, highlighted_diff)
      highlighted_diff.highlight!([diff_entry])

      syntax_highlighted_lines = highlighted_diff.colorized_lines(diff_entry)&.freeze
      syntax_highlighted_lines&.each(&:freeze)

      diff_entry.enumerator.map do |line|
        line = T.let(line, GitHub::Diff::Line)

        if syntax_highlighted_lines
          html = syntax_highlighted_lines[line.position]
          related_html = line.related_line ? syntax_highlighted_lines[line.related_line.position] : nil
          html = mark_intra_line_changes_html(line, html, related_html)
        else
          html = \
            if line.related_line
              mark_intra_line_changes(line)
            else
              sanitize_html_for_unhighlighted_diff_line_with_no_related_lines(line)
            end
        end

        html = ERB::Util.h(html)
        html.chomp!
        html.gsub!("\r", "")
        html = "<br>" unless html.present?

        {
          type: line.type.to_s.upcase,
          blobLineNumber: line.current,
          text: line.text,
          position: line.position,
          html: html,
          left: line.left == -1 ? nil : line.left,
          right: line.right == -1 ? nil : line.right,
        }
      end
    end
  end
end
