# typed: true
# frozen_string_literal: true

require "cvss_suite"

class CvssVectorStringValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    unless value.blank? || CvssSuite.new(value).valid?
      record.errors.add(attribute, "is invalid")
    end
  end
end
