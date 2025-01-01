# typed: true
# frozen_string_literal: true

module SlashCommands
  class EmbeddedCommandValidator < UI::Validator
    VALID_TOP_LEVEL_KEYS = %w(
      trigger
      title
      description
    )

    def validate!
      unless schema.is_a?(Hash)
        errors.add(:base, "Expected schema to be an hash of elements, but was #{backtick(schema.class.name)}")
        return
      end

      validate_expected_keys(:schema, VALID_TOP_LEVEL_KEYS, schema.keys)
    end
  end
end
