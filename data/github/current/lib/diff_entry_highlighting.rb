# typed: strict
# frozen_string_literal: true

class DiffEntryHighlighting
  include ActionView::Helpers::TagHelper

  sig { returns(GitHub::Diff::Entry) }
  attr_reader :diff_entry

  sig { params(diff_entry: GitHub::Diff::Entry).void }
  def initialize(diff_entry)
    @diff_entry = diff_entry

    ext_name = path.split(".").last
    language = Linguist::Language[ext_name] || Linguist::Language.find_by_extension(path)&.first
    @language_scope = T.let(language&.tm_scope, T.nilable(String))
  end

  sig { returns(String) }
  def path
    diff_entry.path
  end

  sig { returns(T.nilable(T::Array[String])) }
  def highlight_lines
    return unless language_scope && language_scope != "none"

    line_texts = []
    line_scopes = []

    diff_entry.each_line do |line|
      if [:addition, :deletion, :context].include?(line.type)
        line_texts[line.position] = line.text[1..-1].to_s
        line_scopes[line.position] = language_scope
      end
    end

    begin
      highlighted_line_groups = GitHub::Colorize.highlight_many(line_scopes, line_texts, code_snippet: true)
      highlighted_line_groups.map { |lines| lines && safe_join([" "] + lines) } if highlighted_line_groups.present?
    rescue GitHub::Colorize::RPCError
      # Ignore as fallback will be used
      nil
    end
  end

  private

  sig { returns(T.nilable(String)) }
  attr_reader :language_scope
end
