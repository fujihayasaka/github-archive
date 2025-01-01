# typed: true
# frozen_string_literal: true

class AccessTokenGeneratable
  HASHED_TOKEN_DIGEST = Digest::SHA256
  class << self
    # Public: Generates a new random token pair, unhashed and hashed.
    #
    # access_token_prefix - The prefix for the token.
    # access_token_bytes - The number of bytes for the token.
    # access_token_formatter - The formatter for the token.
    #
    # Returns base64 String and base64 hashed version of the first String.
    def generate_random_token_pair(access_token_prefix:, access_token_bytes: 30, access_token_formatter: :alphanumeric)
      random_token = generate_random_token(access_token_bytes, access_token_formatter)
      full_token = access_token_prefix + random_token + checksum(random_token)
      [full_token, hash_token(full_token)]
    end

    # Public: Hash token for server side persistence.
    #
    # token - A String
    #
    # Returns hashed base64 String.
    def hash_token(token)
      HASHED_TOKEN_DIGEST.base64digest(token)
    end

    # Public: validate the checksum for the token string provided
    #
    # token - A string
    #
    # This method will remove a prefix before an _ if it is present.
    #
    # This method will return false if the string is shorter than 7 characters, since
    # removing the "checksum" portion of a 6 character string will result in an
    # empty string. The checksum of an empty string is "000000", but it would be possible
    # to trigger false positives if we allowed this.
    #
    # Returns true or false
    def valid_checksum?(token)
      return false unless token.present?

      provided_checksum = token[-6..-1]
      return false unless provided_checksum.present?

      # This is the token without the prefix
      checksum_string = token.split("_", 2).last
      # This is the token without the checksum
      checksum_string = checksum_string[0..-7]
      return false unless checksum_string.present?

      calculated_checksum = checksum(checksum_string)

      SecurityUtils.secure_compare(calculated_checksum, provided_checksum)
    end

    private

    # Internal: Generate a new random token value.
    #
    # access_token_bytes - The number of bytes for the token.
    # access_token_formatter - The formatter for the token.
    #
    # Returns a base64 String.
    def generate_random_token(access_token_bytes, access_token_formatter)
      SecureRandom.send(access_token_formatter, access_token_bytes)
    end

    def checksum(token)
      crc_value = Zlib.crc32(token)
      Base62.encode(crc_value, min_length: 6)
    end
  end
end
