# typed: true
# frozen_string_literal: true

module Pages
  module BuildTypes
    class SelectItemComponent < ApplicationComponent
      attr_reader :build_type, :checked

      def initialize(build_type:, checked: false, disabled: false)
        @build_type = build_type
        @checked = checked
        @disabled = disabled
      end

      def name
        Pages::BuildTypes::SelectItemComponent.item_name(build_type)
      end

      def description
        Pages::BuildTypes::SelectItemComponent.description(build_type)
      end

      def disabled?
        @disabled
      end

      def self.item_name(build_type)
        case build_type
        when :workflow
          "GitHub Actions"
        when :legacy
          "Deploy from a branch"
        end
      end

      def self.description(build_type)
        case build_type
        when :workflow
          "Best for using frameworks and customizing your build process"
        when :legacy
          "Classic Pages experience"
        end
      end
    end
  end
end
