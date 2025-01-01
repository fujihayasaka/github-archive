# typed: true
# frozen_string_literal: true

# Public: An ActiveRecord column type for values containing Integer arrays. Uses a simple binary
# serialization format to store the values in the database with minimal compression.  Intended as an alternative
# to CompressedIntegerArray when data needs to be writable by non-Monolith services (e.g. Go services).
#
# The serialized value is a base64-encoded binary string containing the MessagePack serialized
# representation of the array of Integers.
#
# This class is used by ActiveRecord to serialize and deserialize the values of attributes
# of this type.
class PackedIntegerArray < ActiveRecord::Type::Binary
  # Public: A class for storing an unpacked Integer Array.
  class Array < ::Array
    def self.from(other)
      new.replace(other)
    end
  end

  def type
    :packed_integer_array
  end

  # Public: generate an array of Integers by unpacking the specified binary string value.
  #
  # value - a packed binary string
  #
  # Returns nil if the specified value is nil, or an array of Integers otherwise.
  def deserialize(value)
    value = super
    return nil if value.nil?

    GitHub.dogstats.distribution_time("packed_integer_array.deserialize.dist.time") do
      MessagePack.unpack(Base64.decode64(value))
    end
  end

  def cast(value)
    if value.is_a?(Data)
      value.to_s
    else
      value
    end
  end

  # Public: generate a compressed binary string by packing the Integers in the specified
  # Array value.
  #
  # value - an array of integers
  #
  # Returns nil if the specified value is nil, or a packed string otherwise.
  def serialize(value)
    return nil if value.nil?

    GitHub.dogstats.distribution_time("packed_integer_array.serialize.dist.time") do
      super(Base64.encode64(MessagePack.pack(value)))
    end
  end

  # Public: whether the specified current/deserialized value is different from the specified
  # old/serialized value.
  #
  # Used by ActiveRecord to determine whether an attribute of this type has `changed?` and should
  # be updated in the database.
  #
  # Returns true if the values are different, false otherwise.
  def changed_in_place?(raw_old_value, current_value)
    deserialize(raw_old_value) != current_value
  end
end
