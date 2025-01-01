# typed: true
# frozen_string_literal: true

module StructuredTemplates
  module Elements
    class MultiSelectComponent < StructuredTemplates::Elements::BaseComponent
      private

      def has_description?
        element.description.present?
      end

      def description_id
        "description-#{element.id}"
      end

      def required?
        element.required
      end

      def options
        element.options.map do |option|
          GitHub::Menu::CheckboxComponent.new(
            checked: false,
            name: "#{base_form_param}[#{element.id}][]",
            id: "#{base_form_param}_#{element.id}_#{option}",
            input_classes: "js-session-resumable",
            text: option,
            value: option,
            required: required?,
          )
        end
      end

      def description
        GitHub::Goomba::MarkdownPipeline.to_html(element.description)
      end
    end
  end
end
