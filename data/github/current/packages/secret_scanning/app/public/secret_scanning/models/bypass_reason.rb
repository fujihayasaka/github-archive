# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "secret_scanning_proto"

module SecretScanning
  module Models
    class BypassReason
      extend T::Sig

      FALSE_POSITIVE = :false_positive
      USED_IN_TESTS = :used_in_tests
      WILL_FIX_LATER = :will_fix_later

      # Get all allowed values for this enum
      sig { returns(T::Array[Symbol]) }
      def self.values
        [
          FALSE_POSITIVE,
          USED_IN_TESTS,
          WILL_FIX_LATER,
        ]
      end

      # Get string representations of all allowed values for this enum
      sig { returns(T::Array[String]) }
      def self.string_values
        values.map(&:to_s)
      end

      # Return the proto enum value for the given bypass reason
      sig { params(reason: String).returns(Integer) }
      def self.to_proto_enum(reason)
        reason = reason.upcase

        case reason
        when "FALSE_POSITIVE"
          GitHub::Proto::SecretScanning::Scans::V1::BypassReason::FALSE_POSITIVE
        when "USED_IN_TESTS"
          GitHub::Proto::SecretScanning::Scans::V1::BypassReason::USED_IN_TESTS
        when "WILL_FIX_LATER"
          GitHub::Proto::SecretScanning::Scans::V1::BypassReason::WILL_FIX_LATER
        else
          raise ArgumentError
        end
      end

      sig { params(proto_type: Symbol).returns(Symbol) }
      def self.from_proto(proto_type)
        case GitHub::Proto::SecretScanning::Scans::V1::BypassReason.resolve(proto_type)
        when GitHub::Proto::SecretScanning::Scans::V1::BypassReason::FALSE_POSITIVE
          SecretScanning::Models::BypassReason::FALSE_POSITIVE
        when GitHub::Proto::SecretScanning::Scans::V1::BypassReason::USED_IN_TESTS
          SecretScanning::Models::BypassReason::USED_IN_TESTS
        when GitHub::Proto::SecretScanning::Scans::V1::BypassReason::WILL_FIX_LATER
          SecretScanning::Models::BypassReason::WILL_FIX_LATER
        else
          raise ArgumentError
        end
      end
    end
  end
end
