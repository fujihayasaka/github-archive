# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # HTML filter that replaces $ math $ syntax with a wrapped `<math-renderer>` element
  class MathInlineFilter < MathBaseFilter
    MATH_NOTATION_PATTERN = /
      (?<=^|\s|[(])                    # match beginning of the string, whitespace, or an opening parenthesis
      (\${1,2})                        # match a starting inline math statement that begins with one or two dollar characters
      ((?:[^$\s]|\\\$)(?:[^\$]|\\\$)*) # match presumed math content, cannot start with a dollar character or whitespace
      (?<!\\)\1                        # match an unescaped closing math block delimiter that matches the starting math block delimiter
      (\W|\z)                          # match the end of the string or a non-word character
    /x

    OTHER_MATH_NOTATION_PATTERN = /
      (?<=^|\s|[(])
      (\${2})                           # two and only two dollar_sign
      ([^$\s](?:[^\$\\]|\\.|\$[^\$])*)  # cannot start with dollar_sign or whitespace; cannot start with dollar_sign or backslash OR starts with backslash followed by anything OR starts with dollar sign and not followed by dollar sign
      (?<!\\)\1
      (\W|\z)
    /x

    UNION_OF_NOTATION_PATTERNS = Regexp.union(MATH_NOTATION_PATTERN, OTHER_MATH_NOTATION_PATTERN)

    WRAPPED_MATH_DELIMETERS_PATTERN = /(?<pre>.)\${1,2}(?<post>.)/
    SQL_QUERY_PATTERN = /SELECT|BEGIN/i
    INTERPOLATION_PATTERN = /\A\${.*\${\z/

    def call
      doc.xpath(".//text()").each do |node|
        next if has_ancestor?(node, IGNORE_TAGS)

        html = replace_inline_math_notation(node.to_html)

        next if html.nil?
        node.replace(html)

        result[:changes] = true
      end

      doc
    end

    def display_math?(content)
      return false if GitHub.flipper[:disable_mathjax].enabled?
      UNION_OF_NOTATION_PATTERNS.match?(content)
    end

    # Users have reported that text that contains $ incidentally but is not math
    # is being rendered as if it were. We cannot reasonable account for every edge case,
    # but we can look for common cases e.g.  "This is content with a '$', and a '$' at the end."
    def incidental_math?(content)
      matches = content.scan(WRAPPED_MATH_DELIMETERS_PATTERN)
      return true if !matches.empty? && matches.all? { |pre, post| pre == post }

      return true if INTERPOLATION_PATTERN.match?(content) # Catch plaintext Ruby-style interpolation (e.g. "either ${a} or ${b}")

      SQL_QUERY_PATTERN.match?(content) # Catch PostgreSQL `$$...$$` function definitions (e.g. heart-services/issues/1291)
    end

    def replace_inline_math_notation(content)
      return unless display_math?(content)

      content.gsub!(UNION_OF_NOTATION_PATTERNS) do |maths|
        next maths if incidental_math?(maths)

        output = "#{$1}#{$2}#{$1}"
        math_renderer_tag(
          output,
          css_class: INLINE_MATH_CSS_CLASS,
          style: INLINE_MATH_STYLE,
        ) + $3
      end
    end
  end
end
