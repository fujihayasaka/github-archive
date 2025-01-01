# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    module RiskAssessment
      class Assessment < T::Struct
        const :can_request_another_assessment, T::Boolean
        const :next_request_available_at, DateTime

        const :last_status_change, DateTime
        const :is_complete, T::Boolean
        const :total_scans_wanted, Integer
        const :total_scans_completed, Integer

        const :total_tokens_found, Integer
        const :total_tokens_found_in_public_repo, Integer
        const :total_tokens_found_push_protected_patterns, Integer
        const :total_tokens_found_non_provider_patterns, Integer

        class TokenTypeResult < T::Struct
          const :name, String
          # TODO Implement repositories count
          const :unique_tokens_found_count, Integer

          sig { override.params(args: T.untyped).returns(T::Hash[String, T.untyped]) }
          def serialize(*args)
            payload = super(args)
            payload["id"] = payload["name"] # Need id for DataTable
            payload
          end
        end
        const :tokens, T::Array[TokenTypeResult]
      end
    end
  end
end
