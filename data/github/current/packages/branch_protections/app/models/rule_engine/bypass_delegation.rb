# typed: strict
# frozen_string_literal: true

module RuleEngine
  module BypassDelegation
    extend T::Sig
    extend T::Helpers

    requires_ancestor { Kernel }

    sig { params(rule_suite: RuleSuite).returns(T.nilable(String)) }
    def create_push_ruleset_bypass_url(rule_suite)
      id = Base64.urlsafe_encode64("push_ruleset_bypass-#{rule_suite.id}")
      repo = rule_suite.repository
      return nil unless repo
      repo = repo.network&.root if repo.fork?
      return nil unless repo

      UrlHelpers.push_ruleset_new_bypass_request_url(repo.owner, repo, id, host: GitHub.url)
    end

    sig { params(request: Exemptions::ExemptionRequest).returns(T.nilable(String)) }
    def push_ruleset_bypass_url(request)
      repo = request.repository
      return nil unless repo
      repo = repo.network&.root if repo.fork?
      return nil unless repo

      UrlHelpers.push_ruleset_bypass_request_url(repo.owner, repo, request.number, host: GitHub.url)
    end

    sig { params(rule_suite: RuleSuite, requester: T.any(User, PublicKey)).returns(T.nilable(Exemptions::ExemptionRequest)) }
    def existing_push_ruleset_request(rule_suite, requester)
      existing_requests = existing_push_ruleset_requests(rule_suite, requester)
        .sort_by { |request| request.resource_owner.created_at }
        .reverse

      existing_request = existing_requests.first

      return nil if existing_request.blank?
      return nil if existing_request.resource_owner != rule_suite && T.must(rule_suite.created_at) >= existing_request.resource_owner.created_at

      existing_request
    end

    sig { params(rule_suite_id: Integer, requester: RuleEngine::Types::Actor, requester_comment: T.nilable(String)).returns(Exemptions::ExemptionRequest) }
    def create_push_ruleset_request!(rule_suite_id, requester, requester_comment = nil)
      suite = RuleEngine::RuleSuite.find_by!(id: rule_suite_id)
      repo = suite.repository&.fork? ? suite.repository&.network&.root : suite.repository
      raise UnauthorizedOnRoot unless repo&.readable_by?(requester)

      existing_requests = existing_push_ruleset_requests(suite, requester)
      existing_requests.each do |request|
        request.status = :cancelled
        request.save!
      end

      Exemptions::ExemptionRequest.create!(
        resource_owner: suite,
        requester: requester,
        resource_identifier: suite.after_oid,
        repository: repo,
        request_type: "push_ruleset_bypass",
        requester_comment:)
    end

    private

    sig { params(rule_suite: RuleSuite, requester: T.any(User, PublicKey)).returns(T::Array[Exemptions::ExemptionRequest]) }
    def existing_push_ruleset_requests(rule_suite, requester)
      Exemptions::ExemptionRequest.pending.not_expired.where(
        request_type: "push_ruleset_bypass",
        resource_owner_type: rule_suite.class.name,
        resource_identifier: rule_suite.after_oid,
        repository_id: T.must(rule_suite.repository).id,
        requester:,
      ).to_a
    end

    class UnauthorizedOnRoot < StandardError; end
  end
end
