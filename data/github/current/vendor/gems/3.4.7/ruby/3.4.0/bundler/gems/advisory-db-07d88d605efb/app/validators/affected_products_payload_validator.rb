# frozen_string_literal: true

class AffectedProductsPayloadValidator < ActiveModel::EachValidator
  VALID_FIELDS = [
    "affected_versions",
    "ecosystem",
    "package",
    "patches",
  ].freeze

  def validate_each(record, attribute, value)
    return unless value

    value.each do |affected_product|
      (affected_product.keys - VALID_FIELDS).each do |invalid_field_name|
        record.errors.add(attribute, "can't have the field #{invalid_field_name}")
      end
    end
  end
end
