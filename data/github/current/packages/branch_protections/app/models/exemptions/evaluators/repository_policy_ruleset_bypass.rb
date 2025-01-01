# typed: strict
# frozen_string_literal: true

module Exemptions
  class Evaluators::RepositoryPolicyRulesetBypass < Exemptions::Evaluators::RulesetBypass
    extend T::Helpers

    REQUEST_TYPE = "repository_policy_ruleset_bypass"

    sig { void }
    def initialize
      super(request_type: REQUEST_TYPE)
    end

    sig { override.returns(String) }
    def self.request_type
      REQUEST_TYPE
    end

    sig { override.params(request: ExemptionRequest).returns(T::Boolean) }
    def post_approval_action?(request)
      request.resource_owner.event_action.post_approval_action?
    end

    sig { override.params(request: ExemptionRequest, reviewer: T.untyped).returns(T.untyped) }
    def post_approval_action(request, reviewer)
      return unless request.compute_status == EvaluationResult::Approved
      return unless post_approval_action?(request)

      result = case request.resource_owner.event_action.operation
      when :delete
        T.must(request.repository).remove(reviewer, synchronous: true)
        request.status = :completed
        request.save
      when :change_visibility
        T.must(request.repository).set_visibility(actor: reviewer, visibility: request.resource_owner.event_action.operation_value)
        request.status = :completed
        request.save
      else
        raise "Unsupported post approval action for #{request.resource_owner.event_action.operation}"
      end
      result
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable(String)) }
    def post_approval_redirect_url(request)
      return unless request.resource_owner.event_action.operation == :delete
      UrlHelpers.org_repositories_path(request.repository&.organization) unless request.repository.nil?
    end
  end
end
