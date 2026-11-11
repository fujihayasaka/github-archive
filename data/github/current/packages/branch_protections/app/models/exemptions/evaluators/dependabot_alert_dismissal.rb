# typed: strict
# frozen_string_literal: true

module Exemptions
  class Evaluators::DependabotAlertDismissal < ExemptionEvaluator
    extend T::Helpers

    sig { void }
    def initialize
      super(request_type: Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE)
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

      # Use the delegated closures class to check reviewer permissions
      repository = request.repository
      return false unless repository

      Dependabot::SecurityProduct::DelegatedClosures.is_valid_reviewer?(repository, reviewer)
    end

    sig { override.params(request: ExemptionRequest, requester: RuleEngine::Types::Actor).returns([T::Boolean, T.nilable(String)]) }
    def is_valid_requester?(request, requester)
      return [false, "Requester is not a user"] if requester.is_a?(PublicKey)

      if request.repository&.can_resolve_vulnerability_alerts?(requester)
        [true, nil]
      else
        [false, "Requester does not have permission to resolve vulnerability alerts"]
      end
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def request_notification_configuration(request)
      {
        subject: "Request to dismiss a Dependabot alert",
        reason: "You are receiving this email because you are an approved reviewer for Dependabot alert dismissal.",
        permalink: permalink(request),
      }
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def response_notification_configuration(request)
      {
        subject: "Your Dependabot alert dismissal request has been reviewed",
        reason: "You are receiving this email because you submitted an alert dismissal request.",
        permalink: permalink(request),
      }
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable(T::Array[Integer])) }
    def notification_user_ids(request)
      return [] unless request.repository&.owner&.organization?
      repo = T.must(request.repository)
      org = T.cast(T.must(repo.owner), Organization)

      # Get users who can review Dependabot dismissal requests
      # Similar to Code Scanning, get reviewers who have permission on this specific repo
      reviewer_ids = Dependabot::SecurityProduct::DelegatedClosures.get_org_reviewer_ids(org)
      reviewers = User.where(id: reviewer_ids)

      # Filter to users who can actually review dismissal requests on this repo
      reviewers = reviewers.filter do |user|
        Dependabot::SecurityProduct::DelegatedClosures.is_valid_reviewer?(repo, user)
      end

      reviewers.map(&:id)
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable(Types::ExemptionRequestDataHash)) }
    def exemption_data_hash(request)
      {
        type: Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE,
        data: [{
          alert_number: request.metadata["alert_number"],
        }],
      }
    end

    sig { override.params(request: ExemptionRequest).returns(String) }
    def permalink(request)
      UrlHelpers.repository_alert_url(T.must(request.repository).owner, request.repository, number: request.metadata["alert_number"], host: GitHub.url)
    end

    sig { override.params(request: ExemptionRequest).returns(T::Boolean) }
    def post_approval_action?(request)
      request.reload.compute_status == EvaluationResult::Approved
    end

    sig { override.params(request: ExemptionRequest, reviewer: T.untyped).returns(T.untyped) }
    def post_approval_action(request, reviewer)
      return unless post_approval_action?(request)

      request.update(status: :approved)

      # When a Dependabot dismissal request is approved, actually dismiss the alert
      alert_number = request.metadata["alert_number"].to_i
      reason = request.metadata["reason"]
      comment = request.requester_comment

      # Use the delegated alert closures service to dismiss the alert
      alert = T.must(request.repository).repository_vulnerability_alerts.find_by(number: alert_number)
      if alert
        alert.dismiss(
          actor: reviewer,
          reason: reason,
          comment: comment
        )
      end
    end
  end
end
