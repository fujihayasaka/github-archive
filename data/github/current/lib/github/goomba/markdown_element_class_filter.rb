# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Adds classes to elements based on the tag name. Classes are prefixed with
  # md- so as not to conflict with default styling, such as the .header class.
  class MarkdownElementClassFilter < NodeFilter
    SELECTOR = Goomba::Selector.new("p, h1, h2, h3, h4, h5, h6, ol, ul, li, a, pre")

    def self.enabled?(context)
      context[:add_markdown_element_classes]
    end

    def selector
      SELECTOR
    end

    def call(node)
      if is_element_node?(node)
        case node.tag
        when :pre                         then add_class(node, "md-pre")
        when :p                           then add_class(node, "md-paragraph")
        when :h1, :h2, :h3, :h4, :h5, :h6 then add_class(node, "md-header")
        when :ol, :ul                     then add_class(node, "md-list")
        when :li                          then add_class(node, "md-list-item")
        when :a                           then add_class(node, "md-link Link--inTextBlock")
        end
      end
      node
    end

    private

    def add_class(element, klass)
      element["class"] = [element["class"], klass].compact.join(" ")
    end
  end
end
