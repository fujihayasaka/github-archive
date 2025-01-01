# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Goomba text filter that replaces LaTeX with math notation
  #
  # Context options:
  #   N/A
  class MathInlineFilter < NodeFilter
    IGNORE_TAGS = GitHub::HTML::MathBaseFilter::IGNORE_TAGS.map { |tag| "#{tag} :text" }.join(", ")
    ALLOWED_TAGS = GitHub::HTML::MathBaseFilter::INLINE_MATH_ALLOWED_TAGS
    SELECTOR = Goomba::Selector.new(match: ALLOWED_TAGS.join(","), reject: IGNORE_TAGS)

    def selector
      SELECTOR
    end

    def self.feature_flags
      [:disable_mathjax]
    end

    def self.enabled?(context)
      !GitHub.flipper[:disable_mathjax].enabled?
    end

    def self.cache_key(context)
      GitHub::HTML::MathBaseFilter.cache_key(context)
    end

    def call(element)
      content = element.to_html
      return nil unless content.count("$") > 1
      return nil if GitHub::HTML::MathBaseFilter::IGNORE_TAGS.any? { |tag| !find_node_ancestor(element, tag).nil? }

      # Goomba / Gumbo does not easily (or at all?) expose a way for us to create
      # new abitrary nodes, or mutate existing ones, so rely on nokogiri to parse the content for us
      filter = GitHub::HTML::MathInlineFilter.new(content, context, result)
      output = filter.call

      return element unless filter.result[:changes]

      Goomba::DocumentFragment.new(output.to_html)
    end
  end
end
