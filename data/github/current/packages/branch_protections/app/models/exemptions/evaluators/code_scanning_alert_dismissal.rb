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
      return false if reviewer.is_a?(PublicKey)

      CodeScanning::AlertDismissalService.is_valid_reviewer?(repository: T.must(request.repository), user: reviewer)
    end

    sig { override.params(request: ExemptionRequest, requester: RuleEngine::Types::Actor).returns([T::Boolean, T.nilable(String)]) }
    def is_valid_requester?(request, requester)
      return [false, "Requester is not a user"] if requester.is_a?(PublicKey)

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
      org = T.cast(T.must(request.repository&.owner), Organization)

      CodeScanning::AlertDismissalService.get_org_reviewer_ids(org)
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable(Types::ExemptionRequestDataHash)) }
    def exemption_data_hash(request)
      {
        type: CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE,
        data: [{
          alert_number: request.metadata["alert_number"],
        }],
      }
    end

    sig { override.params(request: ExemptionRequest).returns(String) }
    def permalink(request)
      UrlHelpers.repository_code_scanning_result_url(T.must(request.repository).owner, request.repository, number: request.metadata["alert_number"], host: GitHub.url)
    end

    sig { override.params(request: ExemptionRequest).returns(T::Boolean) }
    def post_approval_action?(request)
      request.reload.compute_status == EvaluationResult::Approved
    end

    sig { override.params(request: ExemptionRequest, reviewer: T.untyped).returns(T.untyped) }
    def post_approval_action(request, reviewer)
      return unless post_approval_action?(request)

      request.update(status: :approved)

      alert_number = request.metadata["alert_number"].to_i
      resolution = request.metadata["resolution"].to_i
      resolver = T.must(request.requester)
      resolution_note = request.requester_comment
      pr_review_thread_id = request.metadata["pr_review_thread_id"].present? ? request.metadata["pr_review_thread_id"].to_i : nil
      campaign_id = request.metadata["campaign_id"].present? ? request.metadata["campaign_id"].to_i : nil

      CodeScanning::AlertDismissalService.close_alert(repository: T.must(request.repository), alert_number:, resolution:, resolver:, resolution_note:, pr_review_thread_id:, campaign_id:, reviewer:)
    end
  end
end
