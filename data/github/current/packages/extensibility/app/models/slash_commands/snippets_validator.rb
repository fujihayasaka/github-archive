# typed: true
# frozen_string_literal: true

module SlashCommands
  class SnippetsValidator < UI::Validator
    VALID_TOP_LEVEL_KEYS = %w(
      trigger
      title
      description
      surfaces
    )

    OPTIONAL_TOP_LEVEL_KEYS = %w(value value_source)

    def validate!
      unless schema.is_a?(Hash)
        errors.add(:base, "Expected schema to be an hash of elements, but was #{backtick(schema.class.name)}")
        return
      end

      validate_expected_keys(:schema, VALID_TOP_LEVEL_KEYS, schema.keys, optional: OPTIONAL_TOP_LEVEL_KEYS)

      if !schema.key?("value") && !schema.key?("value_source")
        errors.add(backtick("value"), "must provide either a value or a value_source")
      end

      if schema.key?("surfaces")
        if schema["surfaces"].is_a?(Array)
          validate_inclusion(key: "surfaces", values: schema["surfaces"], allowed_values: ::SlashCommands::SUPPORTED_SURFACES.map(&:to_s))
        elsif schema["surfaces"] != SlashCommands::ALL_SURFACE
          errors.add(backtick("surfaces"), "was expected to be an `Array` or the string `all` but was #{backtick(schema["surfaces"])}")
        end
      end
    end
  end
end
