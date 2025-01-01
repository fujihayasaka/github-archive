# typed: false
# frozen_string_literal: true

class ExternalIdentityAttribute < ApplicationRecord::Domain::Users
  belongs_to :external_identity

  attribute :raw_value, UnconvertedStringFromBinary.new

  validate :validate_value_character_set

  # Maximum byte size of the string that can be stored in value column
  RAW_VALUE_THRESHOLD = 255

  # Internal: Generates a identifying key for the attribute.
  # Used by ExternalIdentityAttribute::AssociationExtension
  # to determine equivalency between identity attribute objects and
  # their Hash representations.
  def self.generate_key(scheme, name, value)
    key = [scheme, name, value].join(":")

    Digest::SHA256.hexdigest(key)
  end

  def key
    self.class.generate_key(scheme.downcase, name.downcase, value.downcase)
  end

  # Public: Returns the metadata hash which is parsed from the serialized
  # backing field.
  #
  # Returns a Hash.
  def metadata
    return {} unless metadata_json.present?

    JSON.parse(metadata_json)
  end

  # Public: Saves the given metadata in the serialized JSON field.
  #
  # metadata    - The Hash of metadata to be serialized and stored or `nil` if the
  #               stored metadata should be cleared.
  #
  # Returns the set metadata.
  # Raises ArgumentError if passed metadata isn't a Hash or `nil`.
  def metadata=(metadata)
    case metadata
    when nil
      self.metadata_json = nil
    when Hash
      self.metadata_json = metadata.to_json
    else
      raise ArgumentError, "expected metadata to be nil or a Hash"
    end

    metadata
  end

  # Public: Returns the value field
  #
  # If raw_value field is set for the attribute then we would return raw_value
  # If raw_value field is not set for the attribute then we would return value
  # raw_value is set to be value, when the initial value size is greater than 255 bytes
  #
  # Returns a String.
  def value
    return raw_value if raw_value?
    super
  end

  # Public: Saves the given value in the value column.
  #
  # value    - value of the associated scim or saml attribute
  #
  # Returns the set value.
  def value=(value)
    if value.bytesize <= RAW_VALUE_THRESHOLD
      super
    else
      self.value = self.class.generate_value_digest(value)
      self.raw_value = value
    end

    value
  end

  # Internal: Generates a hash for the value.
  def self.generate_value_digest(value)
    Digest::SHA256.hexdigest(value)
  end

  # Public: A hash representation of the attribute.
  #
  # Returns a Hash.
  def to_hash
    {
      "name"      => name,
      "value"     => value,
      "metadata"  => metadata,
    }
  end

  private

  # Private: Validates the value for 4-byte characters
  #
  # Returns a nothing, sets error on value
  def validate_value_character_set
    return unless value

    if value.match(/[\u{10000}-\u{10FFFF}]/)
      errors.add(:value, "contains invalid 4-byte characters")
    end
  end
end
