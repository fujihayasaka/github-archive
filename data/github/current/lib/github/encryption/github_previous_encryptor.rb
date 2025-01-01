# typed: true
# frozen_string_literal: true

require_relative "encryption_errors"
require "json-schema"

module GitHub
  module Encryption
    class GitHubPreviousEncryptor

      # This regex will match any string that has valid charactes
      # for the column encryption JSON scheme. We run the previous
      # data through this regex before attempting to validate
      # the actual json schema. This prevents any string errors from
      # being raised
      #
      # A-Za-z0-9+/= matches base64 encoded contents
      # \r\n matches newlines within json
      # {}":, matches JSON characters
      # _ matches the unserscores in anti_nonce_exhaustion_data
      # ^$ ensures we match the whole string
      COLUMN_ENCRYPTION_REGEX = /\A[{":A-Za-z0-9\/+=_, }\r\n]+\z/.freeze

      EXPECTED_ENCRYPTED_JSON_SCHEMA = {
        type: "object",
        required: %w[p h],
        properties: {
          p: {
            type: "string",
            format: "base64"
          },
          h: {
            type: "object",
            required: %w[iv at i anti_nonce_exhaustion_data],
            properties: {
              iv: {
                type: "string",
                format: "base64"
              },
              at: {
                type: "string",
                format: "base64"
              },
              i: {
                type: "string",
                format: "base64"
              },
              anti_nonce_exhaustion_data: {
                type: "string",
                format: "base64"
              }
            }
          }
        }
      }.freeze

      BASE64_FORMAT = -> (value) {
        begin
          Base64.strict_decode64(value)
        rescue ArgumentError
          raise ::JSON::Schema::CustomFormatError.new("Expected base64 encoded string")
        end
      }

      def initialize(table:, attribute:)
        @table = table
        @attribute = attribute
        ::JSON::Validator.register_format_validator("base64", BASE64_FORMAT)
      end

      def encrypt(clear_text, key_provider: nil, cipher_options: {})
        GitHub.dogstats.increment("encrypted_column.github_previous_key_provider.encrypt", tags: ["table:#{@table}", "attribute:#{@attribute}"])
        raise NotImplementedError.new("This method should not be called")
      end

      def decrypt(previous_data, key_provider: nil, cipher_options: {})
        previous_data = previous_data.to_s

        if previous_data.valid_encoding? &&
          COLUMN_ENCRYPTION_REGEX.match(previous_data).present? &&
          ::JSON::Validator.validate(EXPECTED_ENCRYPTED_JSON_SCHEMA, previous_data)

          GitHub.dogstats.increment("encrypted_column.github_previous_key_provider.decrypt", tags: ["transposed:true", "table:#{@table}", "attribute:#{@attribute}"])
          raise ActiveRecord::Encryption::Errors::Decryption.new("Attempted a decryption using the GitHubPreviousEncryptor class on a value that matches the column encryption scheme. Perhaps transposition occcurred or there was an error loading the key.")
        end

        GitHub.dogstats.increment("encrypted_column.github_previous_key_provider.decrypt", tags: ["transposed:false", "table:#{@table}", "attribute:#{@attribute}"])
        previous_data
      end
    end
  end
end
