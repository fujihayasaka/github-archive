# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    module RiskAssessment
      class Assessment < T::Struct
        const :can_request_another_assessment, T::Boolean
        const :next_request_available_at, DateTime

        const :requested_at, DateTime
        const :last_status_change, DateTime
        const :is_complete, T::Boolean
        const :total_scans_wanted, Integer
        const :total_scans_completed, Integer

        const :total_tokens_found, Integer
        const :total_tokens_found_in_public_repo, Integer
        const :total_tokens_found_push_protected_patterns, Integer
        const :total_tokens_found_non_provider_patterns, Integer

        const :total_repositories_with_results, Integer
        const :distinct_repos_scanned, Integer

        class TokenTypeResult < T::Struct
          const :name, String
          prop :distinct_repos_count, Integer
          prop :unique_tokens_found_count, Integer

          sig { override.params(args: T.untyped).returns(T::Hash[String, T.untyped]) }
          def serialize(*args)
            payload = super(args)
            payload["id"] = payload["name"] # Need id for DataTable
            payload
          end
        end
        const :tokens, T::Array[TokenTypeResult]

        sig do
          params(
            latest_response: GitHub::Proto::SecretScanning::Api::V1::GetLatestAssessmentResponse,
            tokens_response: GitHub::Proto::SecretScanning::Api::V1::GetTokenTypeResultsResponse,
          ).returns(SecretScanning::Models::RiskAssessment::Assessment)
        end
        def self.from_proto(latest_response, tokens_response)
          assessment = latest_response.assessments.to_a.first
          tokens = tokens_response.results.to_a.map do |token|
            SecretScanning::Models::RiskAssessment::Assessment::TokenTypeResult.new(
              name: token.name,
              distinct_repos_count: token.unique_repos_found_this_token,
              unique_tokens_found_count: token.unique_tokens_found
            )
          end
          SecretScanning::Models::RiskAssessment::Assessment.new(
            can_request_another_assessment: latest_response.can_request_another_assessment,
            next_request_available_at: latest_response.can_request_another_assessment ? DateTime.now : latest_response.next_request_available_at&.to_time&.utc&.to_datetime,
            requested_at: assessment&.requested_at&.to_time&.utc&.to_datetime || DateTime.now,
            last_status_change: assessment&.last_status_change&.to_time&.utc&.to_datetime || DateTime.now,
            is_complete: assessment&.complete || false,
            total_scans_wanted: assessment&.total_scans_wanted || 0,
            total_scans_completed: assessment&.total_scans_complete || 0,
            total_tokens_found: tokens_response.total_tokens_found,
            total_tokens_found_in_public_repo: tokens_response.total_tokens_found_in_public_repos,
            total_tokens_found_push_protected_patterns: tokens_response.total_tokens_found_push_protected_patterns,
            total_tokens_found_non_provider_patterns: tokens_response.total_tokens_found_non_provider_patterns,
            total_repositories_with_results: tokens_response.total_repositories_with_results,
            distinct_repos_scanned: latest_response.distinct_repos_scanned,
            tokens:,
          )
        end
      end
    end
  end
end
