# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Models
    class OnDemandValidation
      sig { returns(T.any(Symbol, Integer)) }
      attr_reader :validity

      sig { returns(T.nilable(Time)) }
      attr_reader :validity_last_checked

      sig { returns(T.nilable(Time)) }
      attr_reader :async_check_requested_at

      sig { returns(T::Boolean) }
      attr_reader :async_check_in_progress

      sig { returns(T.nilable(T::Array[Validity::TokenGroup])) }
      attr_reader :token_groups

      sig do
        params(
          validity: T.any(Symbol, Integer),
          validity_last_checked: T.nilable(Time),
          async_check_requested_at: T.nilable(Time),
          token_groups: T.nilable(T::Array[Validity::TokenGroup]),
          async_check_in_progress: T::Boolean
        ).void
      end
      def initialize(validity:, validity_last_checked:, async_check_requested_at:, token_groups: nil, async_check_in_progress: false)
        @validity = validity
        @validity_last_checked = validity_last_checked
        @token_groups = token_groups
        @async_check_requested_at = async_check_requested_at
        @async_check_in_progress = async_check_in_progress
      end

      sig { params(validation_response: GitHub::Proto::SecretScanning::Api::V2::GetTokenValidationStatusResponse).returns(SecretScanning::Models::OnDemandValidation) }
      def self.new_verification_from_proto_validation_request(validation_response)
        validity = validation_response.validity
        token_groups = validation_response.token_groups.to_a.map { |token_group| SecretScanning::Models::Validity::TokenGroup.from_proto(token_group) }
        validity_last_checked = validation_response.validation_details&.validity_last_checked&.to_time
        async_check_requested_at = validation_response.validation_details&.async_check_requested_at&.to_time
        SecretScanning::Models::OnDemandValidation.new(
          validity: validity,
          validity_last_checked: validity_last_checked,
          token_groups: token_groups,
          async_check_requested_at: async_check_requested_at,
          async_check_in_progress: GitHub::TokenScanning::Service::Token.async_check_in_progress?(async_check_requested_at)
        )
      end

      sig { params(report_response: GitHub::Proto::SecretScanning::Api::V2::ReportTokenResponse).returns(SecretScanning::Models::OnDemandValidation) }
      def self.new_verification_from_proto_report_response(report_response)
        validity = report_response.validity
        validity_last_checked = report_response.validation_details&.validity_last_checked&.to_time
        # Right now reporting is only supported for GitHub tokens. These
        # - never have groups (they're all standalone tokens)
        # - do not have an async validity check process
        # - will never have an async check in progress because the validity check process is synchronous
        # When (and if) we support reporting on other token types, we'll have to have TSS return more information
        # and populate it below.
        SecretScanning::Models::OnDemandValidation.new(
          validity:,
          validity_last_checked:,
          token_groups: nil,
          async_check_requested_at: nil,
          async_check_in_progress: false
        )
      end
    end
  end
end
