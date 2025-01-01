# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    class SectionResourceCardsComponent < ApplicationComponent
      def initialize(section:)
        @section = section
        @items = section&.items
      end

      def render?
        @section.present? && @items.present?
      end
    end
  end
end
