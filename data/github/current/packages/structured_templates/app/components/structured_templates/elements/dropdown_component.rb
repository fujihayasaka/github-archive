# typed: strict
# frozen_string_literal: true

module StructuredTemplates
  module Elements
    class DropdownComponent < StructuredTemplates::Elements::BaseComponent
      private

      sig { returns(T::Boolean) }
      def has_description?
        element.description.present?
      end

      sig { returns(String) }
      def description_id
        "description-#{element.id}"
      end

      sig { returns(T::Boolean) }
      def required?
        element.required
      end

      sig { returns(T.nilable(Integer)) }
      def default_option
        element.default
      end

      sig { returns(String) }
      def select_options
        if default_option.present?
          options_for_select(options, options[T.must(default_option)])
        else
          options_for_select(options)
        end
      end

      sig { returns(T::Array[String]) }
      def options
        no_options = ["None"]
        available_options = element.options
        if required? || default_option
          available_options
        else
          [no_options] + available_options
        end
      end

      sig { returns(String) }
      def id
        "#{base_form_param}_#{element.id}"
      end

      sig { returns(String) }
      def name
        "#{base_form_param}[#{element.id}]"
      end

      sig { returns(T.nilable(String)) }
      def description
        GitHub::Goomba::MarkdownPipeline.to_html(element.description)
      end
    end
  end
end
