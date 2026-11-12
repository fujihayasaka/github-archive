# frozen_string_literal: true

require "cvss_suite"

class CVSSVectorStringValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank? # Presence should be validated separately

    record.errors.add(attribute) unless CvssSuite.new(value).valid?
  end
end
