# typed: strict
# frozen_string_literal: true

module SecretScanning::Util
  module Protobuf
    class Duration
      sig { params(milliseconds: Integer).returns(Google::Protobuf::Duration) }
      def self.from_milliseconds(milliseconds)
        if milliseconds <= 0
          return Google::Protobuf::Duration.new(seconds: 0, nanos: 0)
        end

        if milliseconds > 1000
          seconds = milliseconds / 1000
          nanos = (milliseconds % 1000) * 1_000_000
        elsif milliseconds == 1000
          seconds = 1
          nanos = 0
        else
          seconds = 0
          nanos = milliseconds * 1_000_000
        end

        Google::Protobuf::Duration.new(seconds: seconds, nanos: nanos)
      end
    end

    ## Decode helpers
    # These wrappers only exist cuz #decode isn't typed.

    sig { params(decrypted_bytes: String).returns(GitHub::Proto::SecretScanning::Api::V2::TokenMetadataParts) }
    def self.decode_metadata_parts(decrypted_bytes)
      GitHub::Proto::SecretScanning::Api::V2::TokenMetadataParts.decode(decrypted_bytes)
    end
  end
end
