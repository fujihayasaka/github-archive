# typed: strict
# frozen_string_literal: true

module Exemptions
  class Evaluators::SecretScanningClosureRequestBypass < ExemptionEvaluator
    extend T::Helpers
    include SecretScanning::ExemptionConstants

    sig { void }
    def initialize
      super(request_type: CLOSURE_EXEMPTION_REQUEST_TYPE)
    end

    sig { override.params(request: ExemptionRequest, responses: T::Array[ExemptionResponse]).returns(EvaluationResult) }
    def evaluate(request, responses)
      # The status of this request depends on its most recent response
      latest_response = responses[-1]
      if latest_response&.rejected?
        return EvaluationResult::Rejected
      end
      if latest_response&.approved?
        return EvaluationResult::Approved
      end
      EvaluationResult::Pending
    end

    sig { override.params(request: ExemptionRequest, reviewer: RuleEngine::Types::Actor).returns(T::Boolean) }
    def is_valid_reviewer?(request, reviewer)
      # Users cannot review their own requests.
      return false if request.requester == reviewer

      SecretScanning::Services::DelegatedAlertClosuresService.is_valid_reviewer?(T.must(request.repository), reviewer)
    end

    sig { override.params(request: ExemptionRequest, requester: RuleEngine::Types::Actor).returns([T::Boolean, T.nilable(String)]) }
    def is_valid_requester?(request, requester)
      return [false, "we don't support PublicKeys"] if requester.is_a?(PublicKey)

      # Make sure the requester has read permissions on the repo
      has_repo_read_permission = T.must(request.repository).async_permit?(requester, :read).sync
      return [false, "must have read permissions on the repo"] unless has_repo_read_permission

      [true, nil]
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def request_notification_configuration(request)
      {
        subject: "Request to dismiss a secret scanning alert",
        reason: "You are receiving this email because you are an approved reviewer for secret scanning alert dismissal.",
        permalink: permalink(request),
      }
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def response_notification_configuration(request)
      {
        subject: "Your secret scanning alert dismissal request has been reviewed",
        reason: "You are receiving this email because you submitted an alert dismissal request.",
        permalink: permalink(request),
      }
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable(T::Array[Integer])) }
    def notification_user_ids(request)
      return [] unless request.repository&.owner&.organization?
      org = T.cast(T.must(request.repository&.owner), Organization)

      security_managers = SecurityProduct::SecurityManagers.new(org).users.map { |user| user.id }
      org_admins = org.admins.map { |user| user.id }
      user_ids_with_fgp = SecretScanning::Services::DelegatedAlertClosuresService.get_users_with_fgp_via_custom_roles(org)
      (security_managers + org_admins + user_ids_with_fgp).uniq
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable(Types::ExemptionRequestDataHash)) }
    def exemption_data_hash(request)
      {
        type: SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE,
        data: [{
          secret_type: request.metadata["alert_title"],
          alert_number: request.resource_identifier,
        }]
      }
    end

    sig { override.params(request: ExemptionRequest).returns(String) }
    def permalink(request)
      "#{GitHub.url}/#{request.repository&.name_with_display_owner}/security/secret-scanning/#{request.resource_identifier}"
    end
  end
end
