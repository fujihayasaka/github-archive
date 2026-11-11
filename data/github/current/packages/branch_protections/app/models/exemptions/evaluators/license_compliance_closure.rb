# typed: strict
# frozen_string_literal: true

module Exemptions

  # As noted in DependencyGraph::LicenseComplianceDelegatedClosures, the actions taken on
  # ExemptionRequests come via the osslicensecompliance (OLC) service.
  class Evaluators::LicenseComplianceClosure < ExemptionEvaluator
    extend T::Helpers

    sig { void }
    def initialize
      super(request_type: DependencyGraph::LicenseComplianceDelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE)
    end

    sig { override.params(request: ExemptionRequest, requester: RuleEngine::Types::Actor).returns([T::Boolean, T.nilable(String)]) }
    def is_valid_requester?(request, requester)
      return [false, "Requester is not a user"] if requester.is_a?(PublicKey)

      # This has been validated elsewhere
      [true, nil]
    end

    sig { override.params(request: ExemptionRequest, reviewer: RuleEngine::Types::Actor).returns(T::Boolean) }
    def is_valid_reviewer?(request, reviewer)
      return false if reviewer.is_a?(PublicKey)

      # This has been evaluated elsewhere before OLC updates its data and sends the Hydro message
      true
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

    sig { override.params(request: ExemptionRequest).returns(T::Boolean) }
    def post_approval_action?(request)
      request.reload.compute_status == EvaluationResult::Approved
    end

    sig { override.params(request: ExemptionRequest, reviewer: T.untyped).returns(T.untyped) }
    def post_approval_action(request, reviewer)
      return unless post_approval_action?(request)

      request.update(status: :approved)
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable(T::Array[Integer])) }
    def notification_user_ids(request)
      return [] unless request.repository&.owner&.organization?
      repo = T.must(request.repository)
      org = T.cast(T.must(repo.owner), Organization)

      # Get users who can review license compliance alert dismissal requests
      # Similar to Code Scanning, get reviewers who have permission on this specific repo
      DependencyGraph::LicenseComplianceDelegatedClosures.get_org_reviewer_ids(org)
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def request_notification_configuration(request)
      {
        subject: "Request to close a license compliance alert",
        reason: "You are receiving this email because you are an approved reviewer for license compliance alert closure.",
        permalink: permalink(request),
      }
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def response_notification_configuration(request)
      {
        subject: "Your license compliance alert closure request has been reviewed",
        reason: "You are receiving this email because you submitted an alert closure request.",
        permalink: permalink(request),
      }
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def cancellation_notification_configuration(request)
      {
        subject: "Your license compliance alert closure request has been cancelled",
        reason: "You are receiving this email because you are involved in this closure request.",
        permalink: permalink(request),
      }
    end

    sig { override.params(request: ExemptionRequest).returns(String) }
    def permalink(request)
      UrlHelpers.repository_license_compliance_alert_url(T.must(request.repository).owner, request.repository, number: request.metadata["alert_number"], host: GitHub.url)
    end
  end
end
