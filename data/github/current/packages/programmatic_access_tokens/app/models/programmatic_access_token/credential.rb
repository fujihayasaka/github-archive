# typed: true
# frozen_string_literal: true

module ProgrammaticAccessToken
  class Credential
    attr_reader :id, :expires_at, :token_last_eight

    def initialize(id:, expires_at: nil, token_last_eight: nil)
      @id = id
      @expires_at = expires_at
      @token_last_eight = token_last_eight
    end

    def self.new_from_protobuff(protobuff)
      id = parse_id(protobuff)
      expires_at = parse_expires_at(protobuff)
      token_last_eight = parse_token_last_eight(protobuff)

      self.new(id: id, expires_at: expires_at, token_last_eight: token_last_eight)
    end

    def self.parse_id(protobuff)
      protobuff
        .attributes
        .find { |attr| attr.id == "credential.id" }
        .value
        .integer_value
    end

    def self.parse_expires_at(protobuff)
      time_attr = protobuff
        .attributes
        .find { |attr| attr.id == "credential.expires_at_utc" }

      return if time_attr.nil?

      utc_seconds = time_attr.value.time_value.to_i
      Time.zone.at(utc_seconds)
    end

    def self.parse_token_last_eight(protobuff)
      protobuff
        .attributes
        .find { |attr| attr.id == "token.suffix" }
        .value
        .string_value
    end
  end
end
