# typed: true
# frozen_string_literal: true

module UI
  class FormSchema
    class TemplateValidator < UI::Validator
      TOP_LEVEL_KEYS = %w(
        name
        body
      )

      def validate!
        if !schema.is_a?(Hash) || schema.blank?
          errors.add(:base, "YAML definition is not valid")
          return
        end

        unless schema["name"].is_a?(String)
          errors.add(backtick("name"), "was expected to be a `String` but was #{backtick(schema["name"].class.name)}")
        end

        unless schema["description"].blank? || schema["description"].is_a?(String)
          errors.add(
            backtick("description"),
            "was expected to be a `String` but was #{backtick(schema["description"].class.name)}"
          )
        end

        validator = UI::FormSchema::Validator.new(schema["body"], base_key: "body")
        validator.validate!
        validator.errors.messages.each do |form_key, form_errors|
          form_errors.each do |error|
            errors.add(form_key, error)
          end
        end
      end
    end
  end
end
