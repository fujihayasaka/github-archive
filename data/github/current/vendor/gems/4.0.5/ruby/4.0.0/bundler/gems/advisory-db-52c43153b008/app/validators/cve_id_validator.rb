# frozen_string_literal: true

class CVEIDValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank? # Presence should be validated separately

    record.errors.add(attribute) unless AdvisoryDBToolkit::CVEIDValidator.valid?(value)
  end
end
