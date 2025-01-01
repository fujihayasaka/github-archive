# typed: true
# frozen_string_literal: true
module GitHub::HTML
  # HTML filter that replaces $$ <math> $$ syntax with a wrapped `<math-renderer>` element
  class MathDisplayFilter < MathBaseFilter
    ALLOWED_TAGS = "p | gh"

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
      content.start_with?("$$") && content.end_with?("$$")
    end

    def replace_display_math_notation(node)
      content = node.content.strip
      return nil unless display_math?(content)

      # Markdown transforms underscores to italics which breaks math expressions.
      # Replace <em> tags with underscores.
      if node.to_html =~ /<\/?em>/
        content = node.to_html.gsub!(/<\/?em>/, "_").strip
      end

      # MathJax uses the string \\ to denote a new line.
      # The Goomba pipeline treats \\ as a single escaped \. This behavior is correct
      # from the pipeline's perspective but causes rendering issues in MathJax.
      # So, we look for instances of a \ followed by a new line character (\n), and properly
      # double escape the forward slashes.
      content.gsub!("<br>", "\n")
      content_with_mathjax_newlines = content.split("\\\n").join("\\\\\n")
      output = content_with_mathjax_newlines
      math_renderer_tag(
        output,
        css_class: DISPLAY_MATH_CSS_CLASS,
        style: DISPLAY_MATH_STYLE
      )
    end
  end
end
