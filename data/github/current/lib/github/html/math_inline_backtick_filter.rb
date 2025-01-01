# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # HTML filter that replaces $` math `$ syntax with a wrapped `<math-renderer>` element
  class MathInlineBacktickFilter < MathBaseFilter
    IGNORED_TAGS = IGNORE_TAGS.join("|")
    MATH_NOTATION_PATTERN = /
      (?<!<#{IGNORED_TAGS}>)     (?#lookbehind to ensure what we're looking for is not preceeded by a disallowed tag)
      ((?<!\\)\$<code>)          (?# capture the leading $<code> as long as the leading dollar sign isn't escaped)
      (.*?)                      (?# capture the presumed math content)
      (?<!\\)(<\/code>\$)        (?# capture the closing code tag and dollar sign as long as it's not escaped)
      (?!<\/(#{IGNORED_TAGS})>)  (?# make sure we don't have any forbidden closing tags)
    /x

    ALLOWED_TAGS = INLINE_MATH_ALLOWED_TAGS.join(" | ")

    def call
      doc.xpath(ALLOWED_TAGS).each do |node|
        next if has_ancestor?(node, IGNORE_TAGS)

        html = replace_inline_math_notation(node.inner_html)

        next if html.nil?
        node.inner_html = html

        result[:changes] = true
      end

      doc
    end

    def display_math?(content)
      return false if GitHub.flipper[:disable_mathjax].enabled?
      MATH_NOTATION_PATTERN.match?(content)
    end

    def replace_inline_math_notation(content)
      return nil unless display_math?(content)

      content.gsub!(MATH_NOTATION_PATTERN) do
        # output normal $-delimited inline math between js-inline-math tag
        output = "$#{$2}$"
        math_renderer_tag(
          output,
          css_class: INLINE_MATH_CSS_CLASS,
          style: INLINE_MATH_STYLE,
        )
      end
    end
  end
end
