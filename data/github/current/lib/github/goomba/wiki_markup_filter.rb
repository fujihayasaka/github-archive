# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class WikiMarkupFilter < InputFilter
    def self.feature_flags
      [GitHub::HTML::WikiMarkupFilter::ORG_RUBY_RENDERING_FEATURE_FLAG]
    end

    def self.cache_key(context)
      return unless context[:format] == :org

      GitHub::HTML::WikiMarkupFilter.org_ruby_rendering_enabled? ? "org-ruby-rendering-enabled" : "org-ruby-rendering-disabled"
    end

    def call(input)
      GitHub::HTML::WikiMarkupFilter.new(input, @context).call
    end
  end
end
