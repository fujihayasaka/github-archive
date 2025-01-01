# typed: strict
# frozen_string_literal: true

module RuleEngine
  module BypassDelegation
    extend T::Helpers
    extend self
    requires_ancestor { Kernel }

    sig { params(rule_suite: RuleSuite, request_type: String, repo: T.nilable(Repository)).returns(String) }
    def create_ruleset_bypass_url(rule_suite, request_type, repo = nil)
      repo = T.must(repo || rule_suite.repository)
      id = Base64.urlsafe_encode64("#{request_type}-#{rule_suite.id}")
      UrlHelpers.ruleset_new_bypass_request_url(repo.owner, repo, id, host: GitHub.url)
    end

    sig { params(request: Exemptions::ExemptionRequest, repo: T.nilable(Repository)).returns(String) }
    def ruleset_bypass_url(request, repo = nil)
      repo = T.must(repo || request.repository)
      UrlHelpers.ruleset_bypass_request_url(repo.owner, repo, request.number, host: GitHub.url)
    end

    sig { params(rule_suite: RuleSuite, requester: RuleEngine::Types::Actor, request_type: String, requester_comment: T.nilable(String), repo: T.nilable(Repository)).returns(Exemptions::ExemptionRequest) }
    def create_ruleset_request!(rule_suite, requester, request_type, requester_comment = nil, repo = nil)
      repo = T.must(repo || rule_suite.repository)
      raise UnauthorizedOnRoot unless repo.readable_by?(requester)

      existing_requests = existing_ruleset_requests(rule_suite, requester, request_type)
      existing_requests.each do |request|
        request.status = :cancelled
        request.save!
      end

      Exemptions::ExemptionRequest.create!(
        resource_owner: rule_suite,
        requester: requester,
        resource_identifier: rule_suite.after_oid,
        repository: repo,
        request_type: request_type,
        requester_comment:)
    end

    sig { params(rule_suite: RuleSuite, requester: T.any(User, PublicKey), request_type: String).returns(T.nilable(Exemptions::ExemptionRequest)) }
    def existing_ruleset_request(rule_suite, requester, request_type)
      existing_requests = existing_ruleset_requests(rule_suite, requester, request_type)
        .sort_by { |request| request.resource_owner.created_at }
        .reverse

      existing_request = existing_requests.first

      return nil if existing_request.blank?
      return nil if existing_request.resource_owner != rule_suite && T.must(rule_suite.created_at) >= existing_request.resource_owner.created_at

      existing_request
    end

    private

    sig { params(rule_suite: RuleSuite, requester: T.any(User, PublicKey), request_type: String).returns(T::Array[Exemptions::ExemptionRequest]) }
    def existing_ruleset_requests(rule_suite, requester, request_type)
      Exemptions::ExemptionRequest.pending.not_expired.where(
        request_type: request_type,
        resource_owner_type: rule_suite.class.name,
        resource_identifier: rule_suite.after_oid,
        repository_id: T.must(rule_suite.repository).id,
        requester:,
      ).to_a
    end

    class UnauthorizedOnRoot < StandardError; end
  end
end
