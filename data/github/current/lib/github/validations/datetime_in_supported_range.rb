# typed: true
# frozen_string_literal: true

module GitHub
  module Validations
    # Rails validation that ensures that a field contains a value
    # within the supported range for a datetime column in MySQL.
    #
    # Usage example:
    #
    # validates :some_datetime, datetime_in_supported_range: true
    class DatetimeInSupportedRangeValidator < ActiveModel::EachValidator
      # These are the minimum and maximum values allowed by MySQL for the
      # DATETIME type: https://dev.mysql.com/doc/refman/5.0/en/datetime.html
      TIME_MIN = Time.parse("1000-01-01T00:00:00Z")
      TIME_MAX = Time.parse("9999-12-31T23:59:59Z")

      ERROR_MESSAGE = "is not within the supported date range"

      # Public: Called to validate a given value for a given attribute on a given record.
      def validate_each(record, attribute, value)
        return if value.blank?

        if !self.class.accepted_value_type?(value) || !self.class.datetime_in_supported_range?(value)
          record.errors.add(attribute, ERROR_MESSAGE)
        end
      end

      # Public: Is the provided value an acceptable type for the attribute.
      #
      # value - Value to check.
      #
      # Acceptable types are String and anything that responds to #strftime.
      #
      # Returns Boolean.
      def self.accepted_value_type?(value)
        value.is_a?(String) || value.respond_to?(:strftime)
      end

      # Public: Is the provided value valid for a MySQL DATETIME column.
      #
      # value - Value to check.
      #
      # Returns Boolean.
      def self.datetime_in_supported_range?(value)
        return false if value.blank? || !accepted_value_type?(value)
        time = if value.is_a?(String)
          Time.parse(value)
        else
          value
        end

        time.between?(TIME_MIN, TIME_MAX)
      rescue ArgumentError
        false
      end
    end
  end
end
