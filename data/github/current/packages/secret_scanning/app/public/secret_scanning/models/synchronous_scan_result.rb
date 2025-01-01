# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning
  module Models
    # Result of a synchronous scan operation (typically through the Scans API)
    class SynchronousScanResult
      sig { returns(T::Array[SecretScanning::Models::Secret]) }
      attr_reader :secrets
      sig { returns(T::Boolean) }
      attr_reader :completed
      sig { returns(Integer) }
      attr_reader :num_secrets_found_over_limit
      sig { returns(T::Array[Integer]) }
      attr_reader :used_delegated_bypass_request_ids

      sig { params(secrets: T::Array[Secret], completed: T::Boolean, num_secrets_found_over_limit: Integer, used_delegated_bypass_request_ids: T::Array[Integer]).void }
      def initialize(secrets: [], completed: false, num_secrets_found_over_limit: 0, used_delegated_bypass_request_ids: [])
        @secrets = secrets
        @completed = completed
        @num_secrets_found_over_limit = num_secrets_found_over_limit
        @used_delegated_bypass_request_ids = used_delegated_bypass_request_ids
      end

      sig { returns(Integer) }
      def num_secrets_found
        @secrets.length + @num_secrets_found_over_limit
      end

      sig { params(hash: T.nilable(Hash)).returns(SynchronousScanResult) }
      def self.from_hash(hash)
        return new if hash.nil?

        hash = hash.with_indifferent_access

        secrets = T.let(hash[:secrets] || [], T::Array[Hash])
        new(
          secrets: secrets.map { |p| Secret.from_hash(p) },
          completed: hash[:completed] || false,
          num_secrets_found_over_limit: hash[:num_secrets_found_over_limit] || 0,
          used_delegated_bypass_request_ids: hash[:used_delegated_bypass_request_ids].to_a || []
        )
      end
    end
  end
end
