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
      # We don't support PublicKeys.
      return false if reviewer.is_a?(PublicKey)
      # Users cannot review their own requests.
      return false if request.requester == reviewer

      # The request should belong to an org-owned repo.
      return false unless request.repository
      repo = T.must(request.repository)

      return false unless repo.owner.is_a?(Organization)

      org = T.cast(repo.owner, Organization)

      # The reviewer must have the FGP for the org.
      org.has_review_delegated_alert_closure_fgp?(reviewer)
    end

    sig { override.params(request: ExemptionRequest, requester: RuleEngine::Types::Actor).returns([T::Boolean, T.nilable(String)]) }
    def is_valid_requester?(request, requester)
      return [false, "we don't support PublicKeys"] if requester.is_a?(PublicKey)

      # Users with the resolve_secret_scanning_alerts FGP can submit closure requests.
      has_resolve_secret_scanning_fgp = T.must(request.repository).async_secret_scanning_check_fgp_permissions(requester, :resolve_secret_scanning_alerts).sync

      return [false, "must have the 'resolve secret scanning alerts' FGP"] unless has_resolve_secret_scanning_fgp
      [true, nil]
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def request_notification_configuration(request)
      nil
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def response_notification_configuration(request)
      nil
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable(T::Array[Integer])) }
    def notification_user_ids(request)
      # Users with the review delegated alert closure FGP
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable(Types::ExemptionRequestDataHash)) }
    def exemption_data_hash(request)
      nil
    end

    sig { override.params(request: ExemptionRequest).returns(String) }
    def permalink(request)
      ""
    end
  end
end
