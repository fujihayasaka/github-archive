# typed: strict
# frozen_string_literal: true

module SecretScanning
  module BypassDelegation
    extend T::Helpers

    requires_ancestor { Kernel }

    sig { params(repo: T.nilable(Repository), rule_suite_id: T.nilable(Integer), resource_id: String).returns(T.nilable(String)) }
    def create_secret_scanning_bypass_url(repo, rule_suite_id, resource_id)
      return nil unless rule_suite_id
      return nil unless repo
      id = generate_bypass_url_hash(rule_suite_id, resource_id)

      UrlHelpers.secret_scanning_new_bypass_request_url(repo.owner, repo, id,
        host: GitHub.multi_tenant_enterprise? ? GitHub.host_name_with_tenant : GitHub.host_name,
        protocol: GitHub.scheme)
    end

    sig { params(rule_suite_id: Integer, resource_id: String).returns(String) }
    def generate_bypass_url_hash(rule_suite_id, resource_id)
      Base64.urlsafe_encode64("secret_scanning-#{rule_suite_id}-#{resource_id}")
    end

    sig { params(request: Exemptions::ExemptionRequest).returns(T.nilable(String)) }
    def self.secret_scanning_bypass_url(request)
      repo = request.repository
      return nil unless repo
      repo = repo.network&.root if repo.fork?
      return nil unless repo

      UrlHelpers.secret_scanning_bypass_request_url(repo.owner, repo, request.number, host: GitHub.url)
    end

    sig { params(rule_suite: RuleEngine::RuleSuite, requester: T.any(User, PublicKey), resource_identifier: String).returns(T.nilable(Exemptions::ExemptionRequest)) }
    def existing_secret_scanning_request(rule_suite, requester, resource_identifier)
      # First see if there's a single existing request for this rule suite, regardless of status.
      # If yes, we want to redirect to it.
      existing_requests_for_rule_suite = Exemptions::ExemptionRequest.not_expired.where(
        request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
        resource_owner_type: rule_suite.class.name,
        resource_owner_id: rule_suite.id,
        resource_identifier: resource_identifier,
        repository_id: T.must(rule_suite.repository).id,
        requester: requester,
      )
      if existing_requests_for_rule_suite.length == 1
        return existing_requests_for_rule_suite[0]
      end

      # If not, see if there's an existing request for the same commit OIDs + ref name, that is not rejected.
      existing_requests = existing_secret_scanning_requests_for_ref_and_commits(rule_suite, requester, resource_identifier, false)
        .sort_by { |request| request.resource_owner.created_at }
        .reverse

      existing_request = existing_requests.first

      return nil if existing_request.blank?

      existing_request
    end

    sig { params(rule_suite_id: Integer, requester: RuleEngine::Types::Actor, resource_id: String, reason: String, requester_comment: T.nilable(String)).returns(Exemptions::ExemptionRequest) }
    def create_secret_scanning_request!(rule_suite_id, requester, resource_id, reason, requester_comment = nil)
      suite = RuleEngine::RuleSuite.find_by!(id: rule_suite_id)
      repo = suite.repository
      raise UnauthorizedOnRoot unless repo&.readable_by?(requester)

      existing_requests = existing_secret_scanning_requests_for_ref_and_commits(suite, requester, resource_id, true)
      existing_requests.each do |exemption_request|
        exemption_request.status = :cancelled
        exemption_request.save!
      end

      bypass_placeholder, error_message = SecretScanning::Services::PushProtectionService.get_bypass_placeholder(repo, T.cast(requester, User), resource_id)
      if !bypass_placeholder.nil? && error_message.nil?
        label = bypass_placeholder.token_metadata.label
      end

      GitHub.logger.info(
        "SecretScanningDelegatedBypass: Creating bypass request",
        "rule_suite_id": suite.id,
        "requester_id": requester.id,
        "requester_type": requester.class.name,
        "resource_id": resource_id,
        "repo_id": repo.id
      )

      Exemptions::ExemptionRequest.create!(
        resource_owner: suite,
        requester: requester,
        resource_identifier: resource_id,
        repository: repo,
        request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
        expires_at: 1.week.from_now.floor(0),
        metadata: {
          "reason": reason,
          "label": label,
        },
        requester_comment:)
    end

    private

    sig { params(rule_suite: RuleEngine::RuleSuite, requester: T.any(User, PublicKey), resource_identifier: String, include_rejected: T::Boolean).returns(T::Array[Exemptions::ExemptionRequest]) }
    def existing_secret_scanning_requests_for_ref_and_commits(rule_suite, requester, resource_identifier, include_rejected)
      # Return all secret scanning ExemptionRequests that are:
      # - Pending
      # - With an approved ExemptionResponse
      # - With the same resource_id
      # - If include_rejected is true, also includes requests with a rejected ExemptionResponse
      # - Have a RuleSuite (resource owner) with the same before_oid, after_oid, and ref_name as the rule_suite
      not_expired_requests = Exemptions::ExemptionRequest.not_expired.where(
        request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE,
        resource_owner_type: rule_suite.class.name,
        resource_identifier: resource_identifier,
        repository_id: T.must(rule_suite.repository).id,
        requester: requester,
      )

      not_expired_requests.filter do |exemption_request|
        next false unless exemption_request.status == "pending" || (include_rejected && exemption_request.status == "rejected")
        exemption_request.resource_owner.before_oid == rule_suite.before_oid && exemption_request.resource_owner.after_oid == rule_suite.after_oid && exemption_request.resource_owner.ref_name == rule_suite.ref_name
      end
    end

    class UnauthorizedOnRoot < StandardError; end
  end
end
