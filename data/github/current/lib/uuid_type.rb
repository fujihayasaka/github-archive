# typed: true
# frozen_string_literal: true

# Class used to wrap a binary(16) object for read/writes
class UUIDType < ActiveRecord::Type::Binary
  # Converts a value from database input to the appropriate ruby type.
  # Converts from byte array to String
  def deserialize(value)
    return value if value.nil?
    SimpleUUID::UUID.new(super(value)).to_guid
  end

  # Casts a value from the ruby type to a type that the database knows how to understand.
  # Casts string to byte array (binary(16))
  def serialize(value)
    return value if value.nil?
    super(SimpleUUID::UUID.new(value).bytes)
  end
end
