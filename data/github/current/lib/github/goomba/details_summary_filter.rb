# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Ensures <details> elements have a <summary> child for accessibility.
  #
  # When a <details> element doesn't have a <summary>, screen readers may not
  # properly announce the expand/collapse state. This filter adds a default
  # <summary>Details</summary> element to any <details> missing one.
  class DetailsSummaryFilter < NodeFilter
    SELECTOR = Goomba::Selector.new("details")
    DEFAULT_SUMMARY_TEXT = "Details"

    def selector
      SELECTOR
    end

    def call(node)
      return node if has_summary_child?(node)

      prepend_default_summary(node)
    end

    private

    def has_summary_child?(node)
      first_element_child = node.children.find { |child| is_element_node?(child) }
      first_element_child&.tag == :summary
    end

    def prepend_default_summary(node)
      inner_content = safe_html_if_sanitized(node.inner_html)
      summary_element = helpers.content_tag(:summary, DEFAULT_SUMMARY_TEXT)

      helpers.content_tag(:details, summary_element + inner_content, node.attributes.to_h)
    end

    def helpers
      ActionController::Base.helpers
    end
  end
end
