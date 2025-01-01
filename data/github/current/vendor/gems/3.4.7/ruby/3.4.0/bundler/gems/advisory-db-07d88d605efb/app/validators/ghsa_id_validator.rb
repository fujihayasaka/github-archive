# frozen_string_literal: true

class GHSAIDValidator < ActiveModel::EachValidator
  extend AdvisoryDBToolkit::GHSAIDValidator

  def validate_each(record, attribute, value)
    return if value.nil? # Presence should be validated separately

    record.errors.add(attribute) unless AdvisoryDBToolkit::GHSAIDValidator.valid?(value)
  end
end
