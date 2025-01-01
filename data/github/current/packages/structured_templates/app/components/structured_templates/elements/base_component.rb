# typed: true
# frozen_string_literal: true

module StructuredTemplates
  module Elements
    class BaseComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
      def initialize(element:, preview: false, templatable: nil, base_form_param:)
        @element         = element
        @preview         = preview
        @templatable     = templatable
        @base_form_param = base_form_param
      end

      private

      attr_reader :element, :templatable, :base_form_param

      def render?
        element.present? && element.valid? && base_form_param.present?
      end

      def preview?
        @preview
      end
    end
  end
end
