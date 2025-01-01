# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Services
    class DelegatedAlertClosuresService

      sig { void }
      def initialize
        @alerts_service = T.let(SecretScanning::Services::AlertsService.new, SecretScanning::Services::AlertsService)
      end

      sig { params(repo: Repository, resource_id: String).returns(T.nilable(Exemptions::ExemptionRequest)) }
      def existing_alert_closure_request(repo, resource_id)
        existing_requests_for_repo_and_alert = Exemptions::ExemptionRequest.not_expired.where(
          request_type: SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE,
          resource_owner_type: repo.class.name,
          resource_owner_id: repo.id,
          resource_identifier: resource_id,
        ).order(created_at: :desc)
        # There should really only be a max of 1 existing request.
        existing_requests_for_repo_and_alert.last
      end

      sig { params(repo: Repository, requester: User, resource_id: String, reason: String, requester_comment: String).returns(Exemptions::ExemptionRequest) }
      def create_alert_closure_request(repo, requester, resource_id, reason, requester_comment)
        token_number = resource_id.to_i
        if token_number.zero?
          raise SecretScanning::Errors::ServiceError.new("resource ID must be an integer")
        end

        # We hopefully won't have more than 1 request per repo and resource ID, but the DB technically allows it.
        existing_request = existing_alert_closure_request(repo, resource_id)
        if !existing_request.nil?
          GitHub.logger.info(
            "SecretScanningDelegatedAlertClosures: Tried to create closure request, but one already exists",
            "requester_id": requester.id,
            "requester_type": requester.class.name,
            "resource_id": resource_id,
            "repo_id": repo.id,
            "exemption_request_ids": existing_request.id
          )
          raise SecretScanning::Errors::ServiceError.new("A request to close this alert has already been made.")
        end

        GitHub.logger.info(
          "SecretScanningDelegatedAlertClosures: Creating closure request",
          "requester_id": requester.id,
          "requester_type": requester.class.name,
          "resource_id": resource_id,
          "repo_id": repo.id
        )

        closure_request = Exemptions::ExemptionRequest.create!(
          requester: requester,
          resource_owner: repo,
          resource_identifier: resource_id,
          repository: repo,
          request_type: SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE,
          expires_at: 1.week.from_now.floor(0),
          metadata: {
            "reason": reason
          },
          requester_comment:
        )

        err = @alerts_service.update_token_with_closure_request_id(repo, requester, token_number, closure_request.id)
        if !err.nil?
          GitHub.logger.warn(
            "SecretScanningDelegatedAlertClosures: Error when updating closure request ID in TSS",
            "requester_id": requester.id,
            "requester_type": requester.class.name,
            "resource_id": resource_id,
            "repo_id": repo.id,
            "closure_request_id": closure_request.id,
          )
          raise SecretScanning::Errors::ServiceError.new("Unable to update closure request ID in TSS: #{err}")
        end
        closure_request
      end
    end
  end
end
