# typed: true
# frozen_string_literal: true

require "diff_line_change_marker"

class DiffGenerator
  include DiffLineChangeMarker
  include ActionView::Helpers::TagHelper

  # original_text - The "deletion" line.
  # new_text - The "addition" line.
  # path (optional)- The path of the file. This used to infer language and generate
  #                  lines that are highlighted for the correct syntax.
  def initialize(original_text, new_text, path)
    @original_text = original_text
    @new_text = new_text
    @path = path
  end

  def generate_diff
    # Treat trailing newline as a new line
    new_lines = "#{new_text}".split("\n", -1)
    original_lines = "#{original_text}".split("\n")

    # if original_lines is empty, this means the suggestion is deleting a
    # newline, which should be rendered as an empty deletion.
    original_lines << "" if original_lines.empty?

    # get syntax highlighted HTML for all the original and new lines
    original_lines_html = syntax_highlight_filter(original_lines)
    new_lines_html = syntax_highlight_filter(new_lines)

    # stitch together the text and highlighted HTML for each line
    original_lines = original_lines.each_with_index.map { |line, index| { text: line, html: original_lines_html[index] } }
    new_lines = new_lines.each_with_index.map { |line, index| { text: line, html: new_lines_html[index] } }

    if new_lines.length == original_lines.length
      diff_lines = original_lines.zip(new_lines)
      deletions, additions = diff_lines.map do |original_line, new_line|
        generate_html(new_line, original_line)
      end.transpose
    elsif original_lines.length == 1
      first_new_line = new_lines.shift || { text: "" }
      deletion, addition = generate_html(first_new_line, original_lines.first)

      additional_additions = new_lines.map { |l| l[:html] }

      additions = [] if new_lines.empty?
      additions ||= [addition, additional_additions].flatten
      deletions = [deletion]
    else
      additions = new_lines.map { |l| l[:html] }
      deletions = original_lines.map { |l| l[:html] }
    end

    [deletions, additions]
  end

  private

  attr_reader :original_text, :new_text, :path

  def generate_html(new_line, original_line)
    original_diff_line = GitHub::Diff::Line.new(type: :deletion, text: original_line[:text] || "")
    new_diff_line = GitHub::Diff::Line.new(type: :addition, text: new_line[:text] || "")

    original_diff_line.related_line = new_diff_line
    new_diff_line.related_line = original_diff_line

    if original_line[:html]&.html_safe? && new_line[:html]&.html_safe?
      [
        mark_intra_line_changes_html(original_diff_line, original_line[:html], new_line[:html], prefixed: false),
        mark_intra_line_changes_html(new_diff_line, new_line[:html], original_line[:html], prefixed: false)
      ]
    else
      # if either the original or new html is nil or not safe to display,
      # render the original text for these lines as a fallback
      [
        mark_intra_line_changes(original_diff_line),
        mark_intra_line_changes(new_diff_line)
      ]
    end
  end

  def language_scope
    return unless path

    @language_scope ||= begin
      ext_name = path.split(".").last
      language = Linguist::Language[ext_name] || Linguist::Language.find_by_extension(path)&.first
      language&.tm_scope
    end
  end

  def valid_language_scope
    return @valid_language_scope if defined?(@valid_language_scope)
    @valid_language_scope = language_scope&.!= "none"
  end

  def syntax_highlight_filter(texts)
    return texts unless language_scope && valid_language_scope

    scopes = [language_scope] * texts.size
    line_groups = GitHub::Colorize.highlight_many(scopes, texts, code_snippet: true)

    # Treelights returned bad or incomplete results - return non-highlighted lines
    return texts if line_groups.blank? || line_groups.any?(&:nil?)

    line_groups.map { |lines| safe_join(lines) }
  rescue GitHub::Colorize::RPCError
    texts
  end
end
