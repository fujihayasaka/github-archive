# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Applies branch badge styling to code coverage comment elements.
  # Matches elements with id="cc-branch" or id="cc-sha" (set by
  # CoveragePullRequestOverviewProcessor) and applies CSS classes
  # post-sanitization, similar to how ColorFilter works.
  class CodeCoverageBranchFilter < NodeFilter
    include ActionView::Helpers::OutputSafetyHelper

    SELECTOR = Goomba::Selector.new("a[id*='cc-'], span[id*='cc-']")

    def selector
      SELECTOR
    end

    def call(node)
      return nil unless is_element_node?(node)

      id = node["id"]
      if id&.end_with?("cc-branch")
        text = helpers.content_tag(:span, node.text_content)
        link_attrs = node.attributes.to_h
        link_attrs.delete("id")
        existing_class = link_attrs["class"]
        link_attrs["class"] = [existing_class, "no-underline"].compact.join(" ")
        link = helpers.content_tag(:a, text, link_attrs)
        helpers.content_tag(:span, link, class: "commit-ref css-truncate user-select-contain expandable")
      elsif id&.end_with?("cc-sha")
        span_attrs = node.attributes.to_h
        span_attrs["class"] = "color-fg-muted commit-ref"
        span_attrs["style"] = "background: none;"
        helpers.content_tag(:span, node.text_content, span_attrs)
      end
    end

    private

    def helpers
      ActionController::Base.helpers
    end
  end
end
