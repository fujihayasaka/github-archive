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
        # Take the latest one
        existing_requests_for_repo_and_alert.first
      end

      sig { params(repo: Repository, requester: User, resource_id: String, reason: String, requester_comment: String).returns(Exemptions::ExemptionRequest) }
      def create_alert_closure_request(repo, requester, resource_id, reason, requester_comment)
        token_number = resource_id.to_i
        if token_number.zero?
          raise SecretScanning::Errors::ServiceError.new("resource ID must be an integer")
        end

        existing_request = existing_alert_closure_request(repo, resource_id)
        # It's possible to create more than one alert closure request (e.g if the first one is denied or cancelled).
        # This is only a problem if the latest request is still open i.e neither cancelled nor pending.
        if !existing_request.nil? && !(existing_request.status == "cancelled" || existing_request.compute_status != Exemptions::ExemptionEvaluator::EvaluationResult::Pending)
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
            "reason": reason,
            "alert_title": SecretScanning::Services::AlertsService.new.get_alert(repo, requester, resource_id.to_i, nil, include_related_alerts: false).first&.label
          },
          requester_comment:
        )

        GitHub.instrument("secret_scanning_closure_request.create", {
          actor: requester,
          repo: repo,
          org: repo.organization,
          number: closure_request.number,
          alert_number: resource_id,
          reason:,
          comment: requester_comment,
        })

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

      sig do
        params(
          exemption_request: Exemptions::ExemptionRequest,
          status: T.nilable(String),
          message: String,
          user: User,
          repo: Repository,
        ).returns([T.nilable(Exemptions::ExemptionResponse), T.nilable(String)])
      end
      def review_exemption_request!(exemption_request:, status:, message:, user:, repo:)
        if status == "approve"
          # TODO: remove this and move to post_approval_action once that work is complete
          alert_number = exemption_request.resource_identifier.to_i
          return [nil, "Invalid alert number - must be > 0"] unless alert_number > 0

          reason = exemption_request.metadata["reason"]

          if !is_valid_reason?(reason)
            return [nil, "Invalid resolution: #{reason}"]
          end

          requester = exemption_request.requester
          if requester.nil?
            return [nil, "Dismissal request has no requester"]
          end

          close_error = @alerts_service.resolve_alert(repository: repo, user: requester, numbers: [alert_number], resolution: reason)

          if close_error != nil
            return [nil, "Failed to close alert: #{close_error}"]
          end

          res = Exemptions::ExemptionResponse.approve!(exemption_request, user, message: message)
          exemption_request.approved!
          GitHub.instrument("secret_scanning_closure_request.approve", {
            actor: user,
            repo: repo,
            org: repo.organization,
            number: exemption_request.number,
            alert_number: exemption_request.resource_identifier,
            request_reviewer_comment: message,
          })
        elsif status == "reject" || status == "deny"
          res = Exemptions::ExemptionResponse.reject!(exemption_request, user, message: message)
          GitHub.instrument("secret_scanning_closure_request.deny", {
            actor: user,
            repo: repo,
            org: repo.organization,
            number: exemption_request.number,
            alert_number: exemption_request.resource_identifier,
            request_reviewer_comment: message,
          })
        else
          return nil, "Invalid status: #{status}"
        end
        [res, nil]
      end

      sig { params(repository: Repository, reviewer: RuleEngine::Types::Actor).returns(T::Boolean) }
      def self.is_valid_reviewer?(repository, reviewer)
        # We don't support PublicKeys.
        return false if reviewer.is_a?(PublicKey)

        return false unless repository.owner.is_a?(Organization)

        org = T.cast(repository.owner, Organization)

        # The reviewer must have read permissions on the repo
        return false unless repository.async_permit?(reviewer, :read).sync

        # The reviewer must have the FGP for the org.
        org.has_review_delegated_alert_closure_fgp?(reviewer)
      end

      sig { params(reason: String).returns(Symbol) }
      def self.ui_reason_to_tss_symbol(reason)
        case reason
        when "false_positive"
          :FALSE_POSITIVE
        when "tests"
          :USED_IN_TESTS
        when "fixed_later"
          :WONT_FIX
        else
          :UNKNOWN
        end
      end

      sig { params(org: Organization).returns(T::Array[Integer]) }
      def self.get_users_with_fgp_via_custom_roles(org)
        SecretScanning::Util::Authorization.get_users_with_fgp_via_custom_roles_for_org(org, :org_review_and_manage_secret_scanning_closure_requests)
      end

      MSG_LIMIT = 2048
      sig { params(message: T.nilable(String)).returns([T::Boolean, T.nilable(String)]) }
      def self.validate_request_message(message)
        message ||= ""
        message = message.strip
        return false, "Message is required" if message.empty?
        return false, "Message exceeds #{MSG_LIMIT} character limit" if message.length > MSG_LIMIT
        [true, nil]
      end

      private

      sig { params(reason: String).returns(T::Boolean) }
      def is_valid_reason?(reason)
        reason.present? && reason.in?(SecretScanning::ExemptionConstants::VALID_REASONS)
      end
    end
  end
end
