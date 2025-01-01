# typed: strict
# frozen_string_literal: true

module Exemptions
  class Evaluators::PushRulesetBypass < ExemptionEvaluator
    extend T::Sig
    extend T::Helpers

    sig { void }
    def initialize
      super(request_type: "push_ruleset_bypass")
    end

    sig { override.params(request: ExemptionRequest, responses: T::Array[ExemptionResponse]).returns(EvaluationResult) }
    def evaluate(request, responses)
      rule_suite = request.resource_owner
      repo = request.repository
      return EvaluationResult::Rejected unless repo && rule_suite && rule_suite.is_a?(RuleEngine::RuleSuite)

      failed_rulesets = rule_suite.rule_runs.filter(&:failed?).map(&:source_ruleset).compact.uniq
      return EvaluationResult::Approved if failed_rulesets.empty?

      results = failed_rulesets.map do |ruleset|
        next EvaluationResult::Rejected unless ruleset.supports_delegated_bypass?
        # If the requester is a bypasser, they can bypass the ruleset without needing a request
        next EvaluationResult::Approved if ruleset.matches_bypassers?(T.must(request.requester), repo)

        valid_responses = responses.filter { |response| ruleset.matches_bypassers?(T.must(response.reviewer), T.must(rule_suite.repository)) }
        valid_responses = valid_responses.filter { |response| response.status != "dismissed" }

        # Record which responses applied to this specific ruleset
        rule_suite.rule_runs
          .filter { _1.source_ruleset == ruleset }
          .each do |run|
            run.delegation_metadata ||= {}
            T.must(run.delegation_metadata)[:valid_responses] = valid_responses
          end

        if valid_responses.empty?
          EvaluationResult::Pending
        elsif valid_responses.any?(&:rejected?)
          EvaluationResult::Rejected
        elsif valid_responses.all?(&:approved?)
          EvaluationResult::Approved
        else
          EvaluationResult::Pending
        end
      end

      if results.all? { |result| result == EvaluationResult::Approved }
        EvaluationResult::Approved
      elsif results.any? { |result| result == EvaluationResult::Rejected }
        EvaluationResult::Rejected
      else
        EvaluationResult::Pending
      end
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable(T::Array[Integer])) }
    def notification_user_ids(request)
      rule_suite = T.cast(request.resource_owner, RuleEngine::RuleSuite)
      failed_rulesets = rule_suite.rule_runs.filter(&:failed?).map(&:source_ruleset).compact.uniq
      return unless failed_rulesets.any?

      failed_rulesets.flat_map do |ruleset|
        ruleset.bypassable_user_ids(T.must(request.repository))
      end
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def request_notification_configuration(request)
      {
        subject: "User has requested bypass for push rules",
        reason: "You are receiving this email because you are an approved bypasser for one of the violated rulesets.",
        permalink: permalink(request),
      }
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def response_notification_configuration(request)
      {
        subject: "Your request to bypass push rules has an update",
        reason: "You are receiving this email because you submitted this request.",
        permalink: UrlHelpers.push_ruleset_bypass_request_url(T.must(request.repository).owner, request.repository, request.number, host: GitHub.url),
      }
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable(Types::ExemptionRequestDataHash)) }
    def exemption_data_hash(request)
      rule_suite = request.resource_owner
      failed_rule_runs = rule_suite.rule_runs.filter(&:failed?)
      violations = failed_rule_runs.map do |rule_run|
        {
          ruleset_id: rule_run.source_ruleset.id,
          ruleset_name: rule_run.source_ruleset.name,
          total_violations: rule_run.violations["total"],
          rule_type: rule_run.rule_impl.display_name
        }
      end
      {
        type: request.request_type,
        data: violations
      }
    end

    sig { override.params(request: ExemptionRequest).returns(String) }
    def permalink(request)
      UrlHelpers.push_ruleset_bypass_request_url(T.must(request.repository).owner, request.repository, request.number, host: GitHub.url)
    end

    sig { override.params(request: ExemptionRequest, reviewer: RuleEngine::Types::Actor).returns(T::Boolean) }
    def is_valid_reviewer?(request, reviewer)
      rule_suite = request.resource_owner
      return false unless rule_suite && rule_suite.is_a?(RuleEngine::RuleSuite)
      failed_rulesets = rule_suite.rule_runs.filter(&:failed?).map(&:source_ruleset).compact.uniq

      return false if failed_rulesets.empty?

      failed_rulesets.any? do |ruleset|
        next unless ruleset.supports_delegated_bypass?
        ruleset.matches_bypassers?(reviewer, T.must(rule_suite.repository))
      end
    end

    sig { override.params(request: ExemptionRequest, requester: RuleEngine::Types::Actor).returns(T::Array[T.untyped]) }
    def is_valid_requester?(request, requester)
      rule_suite = request.resource_owner
      return [false, nil] unless rule_suite && rule_suite.is_a?(RuleEngine::RuleSuite)
      return [false, "Requester must be user who made the push"] if request.requester != rule_suite.actor
      [true, nil]
    end
  end
end
