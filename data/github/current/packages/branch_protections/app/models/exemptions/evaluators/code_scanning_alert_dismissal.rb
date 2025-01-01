# typed: strict
# frozen_string_literal: true

module Exemptions
  class Evaluators::CodeScanningAlertDismissal < ExemptionEvaluator
    extend T::Helpers

    sig { void }
    def initialize
      super(request_type: CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE)
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
      return false unless request.repository&.owner&.organization? # CodeScanningAlertDismissal are only valid for org owned repos
      org = T.must(request.repository&.owner)

      SecurityProduct::SecurityManagers.new(org).users.include?(reviewer)
    end

    sig { override.params(request: ExemptionRequest, requester: RuleEngine::Types::Actor).returns([T::Boolean, T.nilable(String)]) }
    def is_valid_requester?(request, requester)
      if request.repository&.code_scanning_alerts_writable_by?(requester)
        [true, nil]
      else
        [false, "Requester does not have write access to code scanning"]
      end
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def request_notification_configuration(request)
      {
        subject: "Request to dismiss a code scanning alert",
        reason: "You are receiving this email because you are an approved reviewer for code scanning alert dismissal.",
        permalink: permalink(request),
      }
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def response_notification_configuration(request)
      {
        subject: "Your code scanning alert dismissal request has been reviewed",
        reason: "You are receiving this email because you submitted an alert dismissal request.",
        permalink: permalink(request),
      }
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable(T::Array[Integer])) }
    def notification_user_ids(request)
      return [] unless request.repository&.owner&.organization?
      org = T.must(request.repository&.owner)

      SecurityProduct::SecurityManagers.new(org).users.map { |user| user.id }
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable(Types::ExemptionRequestDataHash)) }
    def exemption_data_hash(request)
      {
        type: CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE,
        data: []
      }
    end

    sig { override.params(request: ExemptionRequest).returns(String) }
    def permalink(request)
      UrlHelpers.repository_code_scanning_result_path(T.must(request.repository).owner, request.repository, number: request.metadata["alert_number"])
    end
  end
end
