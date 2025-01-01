# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # When `pandoc` renders RST files, it does not add a `lang` attribute to the
  # `pre` tag like all of our other renderers. Instead it adds a `class`
  # attribute with the language name, preceeded by `souceCode`.
  #
  # This filter attempts to fix that by extracting the language name from the
  # `class` attribute and adding it to the `lang` attribute of the `pre` tag.
  #
  # Related issue https://github.com/github/html_pipeline/issues/156
  # Original PR: https://github.com/github/github/pull/320972
  class PreTagInputFilter < InputFilter
    extend T::Sig

    RST_RENDERER = T.let("pandoc-ruby".freeze, String)
    SOURCE_CODE_LANG_REGEX = %r{<pre class="sourceCode\s+(\w+)">}m

    sig { override.params(context: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def self.enabled?(context)
      context[:entity].present?
    end

    def call(text)
      return "" if text.nil?
      return text unless rst_rendering?

      body = text.dup

      body.gsub(SOURCE_CODE_LANG_REGEX) do
        "<pre lang=\"#{$1}\" class=\"sourceCode #{$1}\">"
      end
    end

    sig { returns(T::Boolean) }
    private def rst_rendering? = result.fetch(:rendered, "") == RST_RENDERER
  end
end
