# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Adds a notranslate class to some tags
  #
  # This prevents e.g. browser extension for automatic translation from translating the content
  # of code blocks and other preformatted elements. Additionally, this is used for our own machine translation
  # e.g. for discussion comments.
  #
  # Example: <code >https://www.github.com</code>
  # Becomes: <code class="notranslate">https://www.github.com</code>
  #
  class NoTranslationFilter < NodeFilter
    NO_TRANSLATE_SELECTORS = %w[
      code
      pre
    ].freeze

    SELECTOR = Goomba::Selector.new(NO_TRANSLATE_SELECTORS.join(", "))

    def selector
      SELECTOR
    end

    def call(html)
      existing = (html["class"] || "").split(/\s+/)
      html["class"] = existing.concat(["notranslate"]).uniq.join(" ")
      html
    end
  end
end
