# typed: true
# frozen_string_literal: true

module Hook::Payload::Formatter

  # Public: Format the given time as UTC in xmlschema format. This method was
  # duplicated from the API to match what users normally expect from an
  # object serialized by the API.
  #
  # Returns a String or nil.
  def time(t)
    t ? t.utc.to_datetime.xmlschema : nil
  end

end
