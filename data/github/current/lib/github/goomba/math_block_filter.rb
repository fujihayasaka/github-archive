# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Goomba text filter that wraps LaTeX math notation fenced in ```math blocks in <math-renderer> tags
  class MathBlockFilter < NodeFilter
    SELECTOR = Goomba::Selector.new(match: "pre[lang='math']")

    def selector
      SELECTOR
    end

    def self.feature_flags
      [:disable_mathjax]
    end

    def self.enabled?(context)
      !FeatureFlag.vexi.enabled_or_raise?(:disable_mathjax) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end

    def self.cache_key(context)
      GitHub::HTML::MathBaseFilter.cache_key(context)
    end

    def call(element)
      if GitHub::HTML::MathBaseFilter::IGNORE_TAGS.any? { |tag| !find_node_ancestor(element, tag).nil? }
        # We should remove the lang attribute so it renders as valid HTML
        element.remove_attribute("lang")
        return nil
      end

      # Goomba / Gumbo does not easily (or at all?) expose a way for us to create
      # new abitrary nodes, or mutate existing ones, so rely on nokogiri to parse the content for us
      filter = GitHub::HTML::MathBlockFilter.new(element.to_html, context, result)
      output = filter.call

      return element unless filter.result[:changes]

      Goomba::DocumentFragment.new(output.to_html)
    end
  end
end
