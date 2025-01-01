# typed: true
# frozen_string_literal: true

module Commit::ReactDiffLinesHelper
  include DiffLineChangeMarker

  # For same functionality in PR context, see PullRequests::PageData::Diffs::Contents::Loader#diff_lines
  def build_diff_line_data(diff, syntax_highlighted_diff, styling_directives: nil)
    show_no_newline_warning = valid_no_new_line_file?(diff.path)
    diff.enumerator.map do |line|
      if syntax_highlighted_diff
        html = syntax_highlighted_diff[line.position]
        related_html = line.related_line ? syntax_highlighted_diff[line.related_line.position] : nil
        html = mark_intra_line_changes_html(line, html, related_html)
      else
        html = line.related_line ? mark_intra_line_changes(line) : sanitize_html_for_unhighlighted_diff_line_with_no_related_lines(line)
      end

      if styling_directives
        styling_directive = styling_directives[line.position]
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
        displayNoNewLineWarning: show_no_newline_warning && line.nonewline?,
        position: line.position,
        stylingDirective: styling_directive,
        left: line.left == -1 ? nil : line.left,
        right: line.right == -1 ? nil : line.right,
      }
    end
  end

  private

  # path - a filename with the extension
  #
  # We only show the no new line warning on certain languages.
  # This method will return true when the language is not in the list.
  def valid_no_new_line_file?(path)
    languages = Linguist::Language.find_by_filename(path)
    languages = Linguist::Language.find_by_extension(path) if languages.empty?

    !languages.any? { |lang| lang.wrap }
  end

  # For INJECTED_CONTEXT line html, the client expects the leading ~ character to be replaced with a single whitespace
  # character (the same leading character used for CONTEXT lines). For syntax highlighted lines and unhighlighted lines
  # with related lines, this is handled as part of building the HTML. For unhighlightable lines without related lines,
  # this method implements the same logic.
  #
  # Making changes? Update duped method PullRequests::PageData::Diffs::Contents::Loader#sanitize_html_for_unhighlighted_diff_line_with_no_related_lines
  sig { params(line: GitHub::Diff::Line).returns(String) }
  def sanitize_html_for_unhighlighted_diff_line_with_no_related_lines(line)
    return line.text unless line.injected_context?
    return line.text unless line.text.start_with?("~")
    # Replace leading tilde with a single whitespace character for consistent handling on the client side
    " #{line.text[1..-1]}"
  end
end
