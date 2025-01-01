# typed: true
# frozen_string_literal: true

module StructuredTemplates
  module Elements
    class InputComponent < StructuredTemplates::Elements::BaseComponent
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

      def attributes
        attrs = {
          class: "form-control js-session-resumable",
          placeholder: element.placeholder,
          value: element.value,
          required: required?,
          disabled: preview?,
        }

        if has_description?
          attrs = attrs.merge({
            "aria-describedby" => description_id,
          })
        end

        attrs.compact
      end

      def description
        GitHub::Goomba::MarkdownPipeline.to_html(element.description)
      end
    end
  end
end
