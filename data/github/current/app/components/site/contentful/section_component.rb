# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    class SectionComponent < ApplicationComponent
      def initialize(section:)
        @section = section
      end

      def render?
        @section.present?
      end

      def call
        case @section.content_type.id
        when "component_section_grid"
          render Site::Contentful::SectionGridComponent.new(section: @section)
        when "component_section_resource_cards"
          render Site::Contentful::SectionResourceCardsComponent.new(section: @section)
        end
      end
    end
  end
end
