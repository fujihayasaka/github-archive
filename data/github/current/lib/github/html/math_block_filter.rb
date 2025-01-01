# typed: true
# frozen_string_literal: true
module GitHub::HTML
  # HTML filter that ```math fenced block syntax with a wrapped `<math-renderer>` element
  # and wraps the inner content in $$ to be interpreted as display math by MathJax
  #
  class MathBlockFilter < MathDisplayFilter
    # unlike the other filters, we're not ignoring <code> tags
    # because the content of <pre> tags get wrapped in <code> tags
    IGNORE_TAGS = %w(pre a b em math-renderer).to_set

    def call
      doc.xpath("pre[@lang='math'] | .//pre[@lang='math']").each do |node|
        next if has_ancestor?(node, IGNORE_TAGS) || has_child?(node, IGNORE_TAGS)

        stripped_content = node.content.strip
        child_math = display_math?(stripped_content) ? stripped_content : "$$#{stripped_content}$$"

        copy_node = node
        copy_node.content = child_math

        replacement = replace_display_math_notation(copy_node)

        next if replacement.nil?

        node.replace(replacement)
        result[:changes] = true
      end

      doc
    end
  end
end
