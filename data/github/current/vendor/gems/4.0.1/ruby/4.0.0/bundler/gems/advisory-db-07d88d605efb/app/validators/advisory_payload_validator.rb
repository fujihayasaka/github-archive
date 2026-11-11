# frozen_string_literal: true

class AdvisoryPayloadValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.nil? # Presence should be validated separately

    record.errors.add(attribute) unless AdvisoryPayload.valid?(data: value)
  end
end
