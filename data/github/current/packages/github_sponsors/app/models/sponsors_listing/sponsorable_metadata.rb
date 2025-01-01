# typed: true
# frozen_string_literal: true

module SponsorsListing::SponsorableMetadata
  extend ActiveSupport::Concern

  # Public: Maximum key-value sponsorable metadata pairs
  MAX_METADATA_PAIRS = 10

  # Public: Maximum character length for sponsorable metadata key
  MAX_METADATA_KEY_LENGTH = 25

  # Public: Maximum character length for sponsorable metadata value
  MAX_METADATA_VALUE_LENGTH = 100

  # Public: Metadata regex prefix for sanitization
  METADATA_KEY_PREFIX_REGEX = /\Ametadata_/

  # Public: Alphanumeric regex for metadata keys and values
  METADATA_ALPHANUMERIC_REGEX = /\A[a-z0-9][a-z0-9\-\_]*\z/i

  # Public: Non-alphanumeric regex for metadata keys and values
  METADATA_NON_ALPHANUMERIC_REGEX = /[^a-z0-9\-\_]/i

  # Public: Returns if sponsorable metadata key is valid
  #
  # key - Sponsorable metadata key
  #
  # Returns a boolean.
  def self.valid_key?(key)
    key = key.gsub(METADATA_KEY_PREFIX_REGEX, "")

    !key.empty? && alphanumeric?(key)
  end

  # Public: Returns if sponsorable metadata value is valid
  #
  # value - Sponsorable metadata value
  #
  # Returns a boolean.
  def self.valid_value?(value)
    !value.empty? && alphanumeric?(value)
  end

  def self.alphanumeric?(value)
    value_match = value.match(METADATA_ALPHANUMERIC_REGEX).to_s
    value_match == value
  end
end
