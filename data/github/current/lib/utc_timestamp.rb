# typed: true
# frozen_string_literal: true

class UtcTimestamp < ActiveRecord::Type::DateTime
  # Converts a value from database input to the appropriate ruby type. The
  # return value of this method will be returned from
  # ActiveRecord::AttributeMethods::Read#read_attribute.
  # This method expects an integer from the database, which it will convert to
  # a UTC Time, or a Time object, which it will also ensure is UTC.
  def deserialize(time_or_int)
    return Time.at(time_or_int).utc if time_or_int
  end

  # Casts a value from the ruby type to a type that the database knows how to
  # understand. This method expects a Time object which it will convert to an
  # integer for the database to store.
  def serialize(time)
    time.to_i if time
  end
end
