# typed: true
# frozen_string_literal: true

class CreateLabelValidator < ActiveModel::Validator
  INVALID_CHARACTERS = [
    "\u0000", # null bytes
    "\u200B" # zero-width space
  ].freeze

  # label should be an instance of Label
  def validate(label)
    return unless label.name.present?

    invalid_characters_regex = Regexp.union(INVALID_CHARACTERS)
    match = label.name.match?(invalid_characters_regex) if label.name.respond_to?(:match)
    label.errors.add(:name, :invalid) if match
  end
end
