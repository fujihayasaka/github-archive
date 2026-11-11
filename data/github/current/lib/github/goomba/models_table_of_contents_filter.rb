# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Removes the pre-provided table of contents and heading from the Markdown output
  class ModelsTableOfContentsFilter < NodeFilter
    include ActionView::Helpers::OutputSafetyHelper

    SELECTOR = Goomba::Selector.new("h1, ul")

    def selector
      SELECTOR
    end

    def call(element)
      # Clear the initial heading
      return "<span></span>" if element.tag == :h1 && element.text_content == "Getting Started"

      # Clear any list directly below the initial heading (we need to go back twice to cover the \n)
      return "<span></span>" if element.tag == :ul &&
        is_element_node?(element.previous_sibling&.previous_sibling) &&
        element.previous_sibling.previous_sibling.tag == :h1

      element
    end
  end
end
