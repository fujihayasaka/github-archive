# typed: true
# frozen_string_literal: true

module AccessTokenGeneratable
  extend T::Helpers
  extend ActiveSupport::Concern

  # Use SHA256 for hashing tokens
  HASHED_TOKEN_DIGEST = Digest::SHA256

  GeneratableTypes = T.type_alias do
    T.all(
      T.any(
        T.class_of(AuthenticationToken),
        OauthAccess,
        RefreshToken
      ),
      AccessTokenGeneratable::TokenMethods
    )
  end

  included do
    T.bind(self, T::Class[GeneratableTypes])
    class_attribute :access_token_prefix
    class_attribute :access_token_bytes, default: 30
    class_attribute :access_token_formatter, default: :alphanumeric

    extend TokenMethods
  end

  module TokenMethods
    # Public: Generates a new random token pair, unhashed and hashed.
    #
    # Returns base64 String and base64 hashed version of the first String.
    def generate_random_token_pair
      T.bind(self, GeneratableTypes)
      random_token = generate_random_token
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
    # Returns a base64 String.
    def generate_random_token
      T.bind(self, GeneratableTypes)
      SecureRandom.send(access_token_formatter, access_token_bytes)
    end

    def checksum(token)
      crc_value = Zlib.crc32(token)
      Base62.encode(crc_value, min_length: 6)
    end
  end

  include TokenMethods
  mixes_in_class_methods(TokenMethods)
end
