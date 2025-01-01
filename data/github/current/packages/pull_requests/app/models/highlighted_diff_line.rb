# typed: true
# frozen_string_literal: true

class HighlightedDiffLine
  include DiffHelper
  include ActionView::Helpers::TagHelper

  DEFAULT_CACHE_CODE = :unknown

  def self.for_line(line, html_lines:, offset: 0, cache_code: DEFAULT_CACHE_CODE)
    if html_lines && offset
      html = html_lines[line.position + offset]
      related_html = html_lines[line.related_line.position + offset] if line.related_line
    end
    new(line, html, related_html, cache_code)
  end

  def initialize(diff_line, html, related_html, cache_code = DEFAULT_CACHE_CODE)
    @diff_line = diff_line
    @html = html
    @related_html = related_html
    @cache_code = cache_code
  end

  def to_html
    if @html.nil?
      html = mark_intra_line_changes(@diff_line)
    else
      html = mark_intra_line_changes_html(@diff_line, @html, @related_html)
    end

    html = html_escape(html)
    html.chomp!
    html.gsub!("\r", "")
    html = html[1..-1].to_s if [:addition, :deletion, :context, :injected_context].include?(@diff_line.type)
    html = "<br>" unless html.present?
    html.html_safe # rubocop:disable Rails/OutputSafety
  end

  def as_json
    {
      type: @diff_line.type,
      text: @diff_line.text,
      html: to_html,
      position: @diff_line.position,
      left: @diff_line.left == -1 ? nil : @diff_line.left,
      right: @diff_line.right == -1 ? nil : @diff_line.right,
      no_newline_at_end: @diff_line.nonewline?,
      cache_code: @cache_code,
    }
  end
end
