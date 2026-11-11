# typed: true
# frozen_string_literal: true

module SecretScanning
  # Represents a payload used to load the push protection bypass page
  # The model is meant to be url encoded and used to pass in any necessary information to the bypass page
  class PushProtectionBypassPayload
    attr_reader :token_type, :token_signature, :token_type_label

    def initialize(token_type, token_signature, token_type_label)
      @token_type = token_type
      @token_signature = token_signature
      @token_type_label = token_type_label
    end

    # Returns the payload as url safe base64
    def to_base64
      Base64.urlsafe_encode64(JSON.generate({
        token_type: @token_type,
        token_signature: @token_signature,
        token_type_label: @token_type_label,
      }))
    end

    # Builds a payload object from its base64 representation
    def self.from_base64(base64_payload)
      error_msg = "invalid payload. Payload must be a valid base64 encoded json string"

      if !base64_payload.is_a?(String) || base64_payload.empty?
        raise ArgumentError, error_msg
      end

      begin
        hash = JSON.parse(Base64.urlsafe_decode64(base64_payload))
      rescue JSON::ParserError, ArgumentError => ex
        raise ArgumentError, error_msg
      end

      token_type = hash["token_type"]
      token_signature = hash["token_signature"]
      token_type_label = hash["token_type_label"]

      if token_type.nil? || token_type.empty?
        raise ArgumentError, error_msg
      end
      if token_signature.nil? || token_signature.empty? || token_signature.length != 64
        raise ArgumentError, error_msg
      end
      if token_type_label.nil? || token_type_label.empty?
        raise ArgumentError, error_msg
      end

      new(token_type, token_signature, token_type_label)
    end
  end
end
