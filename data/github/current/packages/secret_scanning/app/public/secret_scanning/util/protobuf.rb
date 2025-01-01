# typed: true # rubocop:todo Sorbet/StrictSigil
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
  end
end
