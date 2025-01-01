# typed: true
# frozen_string_literal: true

module GitHub::HTML
  # HTML filter that replaces $$ <math> $$ syntax with a wrapped `<math-renderer>` element
  class MathDisplayFilter < MathBaseFilter
    include ActionView::Helpers::OutputSafetyHelper

    ALLOWED_TAGS = "p | gh"
    DISPLAY_DELIMITER = "$$"

    # We sanitize the inside of math nodes for some tags created in markdown processing
    ALLOWED_CHILD_TAGS = %w(em).to_set

    def call
      doc.xpath(ALLOWED_TAGS).each do |node|
        next if has_ancestor?(node, IGNORE_TAGS) || has_child?(node, IGNORE_TAGS - ALLOWED_CHILD_TAGS)

        replacement = replace_display_math_notation(node)

        next if replacement.nil?

        node.children = replacement

        result[:changes] = true
      end

      doc
    end

    def display_math?(content)
      return false if FeatureFlag.vexi.enabled_or_raise?(:disable_mathjax) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      # if the content is less than 5 characters, this could still be true in the cases of $$, $$$, and $$$$
      content.start_with?(DISPLAY_DELIMITER) && content.end_with?(DISPLAY_DELIMITER) && content.length > 4
    end

    def replace_display_math_notation(node)
      # we use content here only because we intend to escape the results later with safe_join
      content = node.content.strip
      return nil unless display_math?(content)

      # Markdown transforms underscores to italics which breaks math expressions.
      # Replace <em> tags with underscores.
      if node.to_html =~ /<\/?em>/
        content = node.children.to_html.gsub!(/<\/?em>/, "_").strip
      end

      render_escaped_math_content(content)
    end

    private def render_escaped_math_content(content)
      # split on all non-escaped $$ delimiters
      split_content = content.split(/(?<!\\)\$\$/)
      # iterate over all of the contents that were split by the $$ delimiter
      # the first index should be blank, since we know the content starts with $$
      # then, every odd index after that will be content wrapped in $$ and should be rendered as math
      # every even index will be the content that was not wrapped in $$ and should be the plain text
      split_mathified = split_content.each_with_index.map do |block, index|
        next if block.empty?
        if index.odd?
          maths = block
          maths.gsub!("<br>", "\n")
          # MathJax uses the string \\ to denote a new line.
          # The Goomba pipeline treats \\ as a single escaped \. This behavior is correct
          # from the pipeline's perspective but causes rendering issues in MathJax.
          # So, we look for instances of a \ followed by a new line character (\n), and properly
          # double escape the forward slashes.
          content_with_mathjax_newlines = maths.split("\\\n").join("\\\\\n")
          math_renderer_tag(
            "#{DISPLAY_DELIMITER}#{content_with_mathjax_newlines}#{DISPLAY_DELIMITER}",
            css_class: DISPLAY_MATH_CSS_CLASS,
            style: DISPLAY_MATH_STYLE
          )
        else
          block
        end
      end

      # after we've rendered any math blocks, we need to re-join the content safely, escaping any HTML in the
      # even indexed blocks above
      safe_join(split_mathified, "")
    end
  end
end
