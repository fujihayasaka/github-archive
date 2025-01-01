# typed: strict
# frozen_string_literal: true

module Exemptions
  class Evaluators::RulesetBypass < ExemptionEvaluator
    extend T::Helpers

    abstract!

    sig { returns(String) }
    def self.request_type
      raise NotImplementedError, "request_type must be implemented by subclasses"
    end

    sig { params(request_type: String).void }
    def initialize(request_type:)
      super(request_type: request_type)
    end

    sig { params(rule_suite: RuleEngine::RuleSuite).returns(String) }
    def self.create_request_url(rule_suite)
      RuleEngine::BypassDelegation.create_ruleset_bypass_url(rule_suite, request_type)
    end

    sig { params(rule_suite: RuleEngine::RuleSuite, requester: RuleEngine::Types::Actor, requester_comment: T.nilable(String)).returns(Exemptions::ExemptionRequest) }
    def self.create_request!(rule_suite, requester, requester_comment = nil)
      RuleEngine::BypassDelegation.create_ruleset_request!(rule_suite, requester, request_type, requester_comment)
    end

    sig { params(rule_suite: RuleEngine::RuleSuite, requester: T.any(User, PublicKey)).returns(T.nilable(Exemptions::ExemptionRequest)) }
    def self.existing_request(rule_suite, requester)
      RuleEngine::BypassDelegation.existing_ruleset_request(rule_suite, requester, request_type)
    end

    sig { params(request: Exemptions::ExemptionRequest).returns(String) }
    def self.url(request)
      RuleEngine::BypassDelegation.ruleset_bypass_url(request)
    end

    sig { override.params(request: ExemptionRequest, responses: T::Array[ExemptionResponse]).returns(EvaluationResult) }
    def evaluate(request, responses)
      rule_suite = request.resource_owner
      repo = request.repository
      requester = request.requester
      return EvaluationResult::Rejected unless repo && rule_suite && rule_suite.is_a?(RuleEngine::RuleSuite)

      return EvaluationResult::Rejected if requester.nil?

      failed_rulesets = rule_suite.rule_runs.filter(&:failed?).map(&:source_ruleset).compact.uniq
      return EvaluationResult::Approved if failed_rulesets.empty?

      results = failed_rulesets.map do |ruleset|
        next EvaluationResult::Rejected unless ruleset.supports_delegated_bypass?
        # If the requester is a bypasser, they can bypass the ruleset without needing a request
        next EvaluationResult::Approved if ruleset.matches_bypassers?(requester, repo)

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
        permalink: permalink(request),
      }
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable(Types::ExemptionRequestDataHash)) }
    def exemption_data_hash(request)
      rule_suite = request.resource_owner
      return unless rule_suite&.rule_runs
      failed_rule_runs = rule_suite.rule_runs.filter(&:failed?)
      violations = failed_rule_runs.map do |rule_run|
        total_violations = rule_run.violations["total"]
        hash = {
          ruleset_id: rule_run.source_ruleset.id,
          ruleset_name: rule_run.source_ruleset.name,
          rule_type: rule_run.rule_impl.display_name
        }
        hash[:total_violations] = total_violations if total_violations

        hash
      end
      {
        type: request.request_type,
        data: violations
      }
    end

    sig { override.params(request: ExemptionRequest, reviewer: RuleEngine::Types::Actor).returns(T::Boolean) }
    def is_valid_reviewer?(request, reviewer)
      return false if request.requester == reviewer

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
      return [false, "Requester must be user who made the ruleset violation"] if request.requester != rule_suite.actor
      [true, nil]
    end

    sig { override.params(request: ExemptionRequest).returns(String) }
    def permalink(request)
      repo = request.repository
      return "" unless repo
      UrlHelpers.ruleset_bypass_request_url(repo.owner, request.repository, request.number, host: GitHub.url)
    end
  end
end
