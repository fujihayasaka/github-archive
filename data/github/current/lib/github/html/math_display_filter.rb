# typed: true
# frozen_string_literal: true
module GitHub::HTML
  # HTML filter that replaces $$ <math> $$ syntax with a wrapped `<math-renderer>` element
  class MathDisplayFilter < MathBaseFilter
    ALLOWED_TAGS = "p | gh"
    DISPLAY_DELIMITER = "$$"
    MATH_NOTATION_PATTERN = /
      (\$\$)                               # match a starting display math statement that begins with two dollar characters and optional new line
      (\n)?                                # match optional new line
      ((?:[^$]|\\\$)(?:(?!\$\$).|\\\$)*) # match presumed math content, cannot start with dollar sign, ignore dollar sign and backslash dollar sign within display
      (?<!\\)\1                            # match an unescaped closing math block delimiter that matches the starting math block delimiter
    /xm                                    # ignore whitespace and enable multiline

    def call
      doc.xpath(ALLOWED_TAGS).each do |node|
        next if has_ancestor?(node, IGNORE_TAGS) || has_child?(node, IGNORE_TAGS)

        replacement = replace_display_math_notation(node)

        next if replacement.nil?

        node.children = replacement

        result[:changes] = true
      end

      doc
    end

    def display_math?(content)
      return false if GitHub.flipper[:disable_mathjax].enabled?
      content.start_with?(DISPLAY_DELIMITER) && content.end_with?(DISPLAY_DELIMITER)
    end

    def replace_display_math_notation(node)
      content = node.content.strip
      return nil unless display_math?(content)

      # Markdown transforms underscores to italics which breaks math expressions.
      # Replace <em> tags with underscores.
      if node.to_html =~ /<\/?em>/
        content = node.to_html.gsub!(/<\/?em>/, "_").strip
      end

      # Find the display blocks when they are one after the other, e.g. $$\n...$$\n$$\n...$$
      content.gsub(MATH_NOTATION_PATTERN) do |maths|
        maths.gsub!("<br>", "\n")
        # MathJax uses the string \\ to denote a new line.
        # The Goomba pipeline treats \\ as a single escaped \. This behavior is correct
        # from the pipeline's perspective but causes rendering issues in MathJax.
        # So, we look for instances of a \ followed by a new line character (\n), and properly
        # double escape the forward slashes.
        content_with_mathjax_newlines = maths.split("\\\n").join("\\\\\n")
        output = content_with_mathjax_newlines
        math_renderer_tag(
          output,
          css_class: DISPLAY_MATH_CSS_CLASS,
          style: DISPLAY_MATH_STYLE
        )
      end
    end
  end
end
