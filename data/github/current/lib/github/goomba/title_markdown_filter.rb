# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Processes a very specific subset of Markdown, suited for issue/PR titles,
  # producing an escaped, HTML-safe output.
  #
  # Currently only supports `inline code`, which becomes <code> tags.
  # No bold/italic/strike, autolinks, titles, tables, lists, etc.
  #
  # It also supports replacing native emoji with html polyfill HTML elements.
  #
  # If we ever come to support other markup in the future, we should explore
  # options other than a regexp to do the transformation.
  class TitleMarkdownFilter < InputFilter
    def self.cache_key(context)
      GitHub::HTML::EmojiFilter.cache_key(context)
    end

    def call(text)
      markdown = html_escape(text).gsub(/(`+)([^`]+)\1/, '<code>\2</code>')
      GitHub::HTML::EmojiFilter.call(markdown).to_html.html_safe # rubocop:disable Rails/OutputSafety
    end
  end
end
