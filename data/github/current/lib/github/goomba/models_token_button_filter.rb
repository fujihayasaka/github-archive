# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Enriches the "generate a PAT" link in Azure-provided content to be its own button
  class ModelsTokenButtonFilter < NodeFilter
    include ActionView::Helpers::OutputSafetyHelper
    include OcticonsHelper

    SELECTOR = Goomba::Selector.new("p")

    def selector
      SELECTOR
    end

    def call(element)
      # we need the closest <p> parent of a <b><a> element, so let's check that we only have the one bold child and that it contains a link
      return unless element.children.count { |c| is_element_node?(c) } == 1
      return unless element.children.find do |c|
        is_element_node?(c) &&
          c.tag == :strong &&
          c.children.first.matches("a[href='https://github.com/settings/tokens?type=beta']")
      end

      component = Marketplace::Models::GetApiKeyComponent.new(
        azure_link: context[:azure_link]
      )
      ApplicationController.render(component, formats: [:html], layout: false)
    end
  end
end
