# typed: strict
# frozen_string_literal: true

class MemexDateTimeFormat
  extend T::Sig

  class FormatError < ArgumentError; end

  # This is the format that we use to validate date time fields for Memex, it is a subset of ISO 8601,
  # and it restricts the year value to 4 digits, and the timezone offset to 2 digits.
  # This is because the Ruby DateTime class (Ex. `DateTime.parse`, and `DateTime.iso8601`)
  # support year values with 5+ digits, which may cause issues with downstream services,
  # this regex validates the timestamp to ensure that it is in the format that we expect.
  DATE_FORMAT = /\A(\d{4})-(\d{2})-(\d{2})T(\d{2})\:(\d{2})\:(\d{2})[+-](\d{2})\:(\d{2})\z/

  sig { params(date_time_string: String).returns(DateTime) }
  def self.parse(date_time_string)
    unless date_time_string.match?(DATE_FORMAT)
      raise FormatError.new("Invalid date time format: #{date_time_string}")
    end

    DateTime.parse(date_time_string)
  end
end
