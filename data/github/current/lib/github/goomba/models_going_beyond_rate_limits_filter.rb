# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Hide the Going beyond rate limits section if the user has enabled the Models billing
  class ModelsGoingBeyondRateLimitsFilter < NodeFilter
    include ActionView::Helpers::OutputSafetyHelper
    include OcticonsHelper

    SELECTOR = Goomba::Selector.new("h2, p")
    CHAPTER_5 = "5. Going beyond rate limits"

    def selector
      SELECTOR
    end

    def call(element)
      if context[:is_billing_enabled]
        return "<span></span>" if element.tag == :h2 && element.text_content == CHAPTER_5

        previous_h2 = element.previous_sibling&.previous_sibling
        return "<span></span>" if element.tag == :p && is_element_node?(previous_h2) && previous_h2.tag == :h2 && previous_h2.text_content == CHAPTER_5
      end

      element
    end
  end
end
