# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Wrap tables in a markdown-accessibility-table tag.
  # The <markdown-accessibility-table> catalyst component dynamically makes tables tabbable
  # when they are horizontally scrollable.
  class TabbableTableFilter < NodeFilter
    SELECTOR = Goomba::Selector.new(match: "table", reject: "table table")

    def selector
      SELECTOR
    end

    def call(node)
      ActionController::Base.helpers.content_tag(
        "markdown-accessiblity-table",
        safe_html_if_sanitized(node.to_html),
      )
    end
  end
end
