# typed: true
# frozen_string_literal: true

require "cvss_suite"

class CvssVectorStringValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?
    cvss = CvssSuite.new(value)
    if cvss.valid?
      return if attribute == :cvss_v3 && valid_cvss_v3?(cvss)
      return if attribute == :cvss_v4 && valid_cvss_v4?(cvss)
    end
    record.errors.add(attribute, "is invalid")
  end

  def valid_cvss_v4?(cvss)
    cvss.version == 4.0
  end

  def valid_cvss_v3?(cvss)
    cvss.version < 4.0
  end
end
