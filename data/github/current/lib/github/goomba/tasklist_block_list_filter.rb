# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Goomba node filter that removes root level `ul` or `ol` elements from the returned HTML document
  class TasklistBlockListFilter < NodeFilter
    include ActionView::Helpers::OutputSafetyHelper

    LIST_ELEMENTS = %w[ul ol].freeze
    # select list elements
    LIST_MATCHERS = LIST_ELEMENTS.join(", ").freeze
    # TODO: Come back to eventually support nested lists, or somehow render nested lists as regular items.
    # For now, we reject nested lists and they will be part of their parent's content.
    # Use array combination to create  a list of all unique combinations of list element nesting
    LIST_REJECTORS = (LIST_ELEMENTS * 2).combination(2).uniq.map { |elems| "#{elems.join(" ")}" }.join(", ").freeze

    # select list elements that are children of a tracking-block element
    SELECTOR = Goomba::Selector.new(match: LIST_MATCHERS, reject: LIST_REJECTORS)

    def selector
      SELECTOR
    end

    def call(node)
      # remove the top level list element from the returned document by replacing it with a document of it's children
      safe_html_if_sanitized(node.inner_html)
    end
  end
end
