# typed: true
# frozen_string_literal: true

module Commit::ReactDiffLinesHelper

  include DiffLineChangeMarker

  def build_diff_line_data(diff, syntax_highlighted_diff)
    diff.enumerator.map do |line|
      if syntax_highlighted_diff
        html = syntax_highlighted_diff[line.position]
        related_html = line.related_line ? syntax_highlighted_diff[line.related_line.position] : nil
        html = mark_intra_line_changes_html(line, html, related_html)
      else
        html = line.related_line ? mark_intra_line_changes(line) : line.text
      end

      html = ERB::Util.h(html)
      html.chomp!
      html.gsub!("\r", "")
      html = "<br>" unless html.present?

      {
        type: line.type.upcase,
        blobLineNumber: line.current,
        text: line.text,
        html: html,
        position: line.position,
        left: line.left == -1 ? nil : line.left,
        right: line.right == -1 ? nil : line.right,
      }
    end
  end
end
