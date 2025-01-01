# typed: strict
# frozen_string_literal: true

module Exemptions
  class Evaluators::PushRulesetBypass < Exemptions::Evaluators::RulesetBypass
    extend T::Helpers

    REQUEST_TYPE = "push_ruleset_bypass"

    sig { override.returns(String) }
    def self.request_type
      REQUEST_TYPE
    end

    sig { void }
    def initialize
      super(request_type: REQUEST_TYPE)
    end

    sig { params(rule_suite: RuleEngine::RuleSuite).returns(String) }
    def self.create_request_url(rule_suite)
      repo = root_repo(rule_suite.repository)
      RuleEngine::BypassDelegation.create_ruleset_bypass_url(rule_suite, REQUEST_TYPE, repo)
    end

    sig { params(rule_suite: RuleEngine::RuleSuite, requester: RuleEngine::Types::Actor, requester_comment: T.nilable(String)).returns(Exemptions::ExemptionRequest) }
    def self.create_request!(rule_suite, requester, requester_comment = nil)
      repo = root_repo(rule_suite.repository)
      RuleEngine::BypassDelegation.create_ruleset_request!(rule_suite, requester, REQUEST_TYPE, requester_comment, repo)
    end

    sig { params(request: Exemptions::ExemptionRequest).returns(String) }
    def self.url(request)
      repo = root_repo(request.repository)
      RuleEngine::BypassDelegation.ruleset_bypass_url(request, repo)
    end

    # For push rules specifically, rules are defined (and bypassed) on the network root repo only
    sig { params(repo: T.nilable(Repository)).returns(T.nilable(Repository)) }
    def self.root_repo(repo)
      repo&.fork? ? repo.network&.root : repo
    end
  end
end
