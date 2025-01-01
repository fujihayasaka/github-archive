# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Goomba node filter that parses the title of a tracking block and returns it as part of the result.
  # The header is removed from the resulting HTML.
  class TasklistBlockTitleFilter < NodeFilter
    TITLE_SELECTORS = (1..6).map { |level| "h#{level}:-goomba-first-child-node" }.join(", ").freeze
    SELECTOR = Goomba::Selector.new(match: TITLE_SELECTORS)

    def selector
      SELECTOR
    end

    def call(node)
      result[:title] = node.text_content
      result[:title_html] = safe_html_if_sanitized(node.inner_html)

      false
    end
  end
end
