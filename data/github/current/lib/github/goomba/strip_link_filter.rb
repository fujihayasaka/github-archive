# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Public: Removes links, replacing them with their contents (e.g., the link text).
  class StripLinkFilter < NodeFilter
    include ActionView::Helpers::OutputSafetyHelper

    SELECTOR = Goomba::Selector.new("a")

    def selector
      SELECTOR
    end

    def call(element)
      child_nodes = element.children
      return false if child_nodes.empty?

      processed_array = child_nodes.map do |child|
        next child.text_content unless child.is_a?(Goomba::ElementNode)
        safe_html_if_sanitized(child.to_html)
      end

      if processed_array.empty?
        false
      else
        safe_join(processed_array, "")
      end
    end
  end
end
