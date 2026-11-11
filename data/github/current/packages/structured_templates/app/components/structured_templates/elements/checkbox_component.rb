# typed: true
# frozen_string_literal: true

module StructuredTemplates
  module Elements
    class CheckboxComponent < StructuredTemplates::Elements::BaseComponent
      def checkboxes
        element.checkboxes
      end

      def has_description?
        element.description.present?
      end

      def description_id
        "description-#{element.id}"
      end

      def description
        GitHub::Goomba::MarkdownPipeline.to_html(element.description)
      end

      def markdownify(label)
        GitHub::Goomba::StructuredTemplatesCheckboxLabelPipeline.to_html(label)
      end
    end
  end
end
