# typed: strict
# frozen_string_literal: true

module Exemptions
  class Evaluators::SecretScanningBypass < ExemptionEvaluator
    extend T::Sig
    extend T::Helpers
    include SecretScanning::Constants

    sig { void }
    def initialize
      super(request_type: EXEMPTION_REQUEST_TYPE)
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
      return false if request.requester == reviewer
      SecretScanning::Services::DelegatedBypassService.can_review_bypass_request?(T.must(request.repository), reviewer)
    end

    sig { override.params(request: ExemptionRequest, requester: RuleEngine::Types::Actor).returns([T::Boolean, T.nilable(String)]) }
    def is_valid_requester?(request, requester)
      rule_suite = request.resource_owner
      return [false, nil] unless rule_suite && rule_suite.is_a?(RuleEngine::RuleSuite)
      if request.requester != rule_suite.actor
        return [false, "must be user who made the push"]
      end
      [true, nil]
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def request_notification_configuration(request)
      {
        subject: "Request to bypass secret scanning push protection",
        reason: "You are receiving this email because you are an approved bypasser for secret scanning push protection.",
        permalink: permalink(request),
      }
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable({ subject: String, reason: String, permalink: String })) }
    def response_notification_configuration(request)
      {
        subject: "Your push protection bypass request has been reviewed",
        reason: "You are receiving this because you submitted this request.",
        permalink: permalink(request),
      }
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable(T::Array[Integer])) }
    def notification_user_ids(request)
      reviewers_source = request.repository
      reviewers_scope = :repository
      if SecretScanning::Features::Repo::DelegatedBypass.new(T.must(reviewers_source)).enabled_by_organization?
        reviewers_source = reviewers_source&.organization
        reviewers_scope = :organization
      end

      bypass_reviewers, error_message = SecretScanning::Services::DelegatedBypassService.get_bypass_reviewers(reviewers_scope, T.must(reviewers_source&.id), T.must(request.requester&.id))
      return [] if bypass_reviewers.nil? || bypass_reviewers.empty? || error_message

      user_ids, team_ids, role_ids = SecretScanning::Services::DelegatedBypassService.split_bypass_reviewers_ids_by_type(bypass_reviewers, T.must(reviewers_source))

      users, teams = SecretScanning::Services::DelegatedBypassService.get_users_teams_from_role_ids(role_ids, T.must(request.repository))

      team_ids.concat(teams.flatten.uniq.pluck(:id)) if teams.any?

      user_ids.concat(Team.member_ids_of(team_ids.flatten.uniq, immediate_only: false)) if team_ids.any?
      user_ids.concat(users.pluck(:id)) if users.any?

      user_ids.flatten.uniq
    end

    sig { override.params(request: ExemptionRequest).returns(T.nilable(Types::ExemptionRequestDataHash)) }
    def exemption_data_hash(request)
      hash = {
        type: EXEMPTION_REQUEST_TYPE,
        data: []
      }
      rule_suite = request.resource_owner
      # We only care about the latest rule run
      rule_run = rule_suite.rule_runs.last
      if rule_run&.insights_ui_metadata&.keys&.include?("secrets")
        matching_secrets = rule_run.insights_ui_metadata["secrets"].filter { |secret| secret["bypass_placeholder_ksuid"] == request.resource_identifier }
        if matching_secrets.size == 1 && matching_secrets.first
          hash[:data] << {
            secret_type: matching_secrets.first["token_metadata"]["label"],
            commits: matching_secrets.first["locations"].map { |location| location["commit_oid"] }
          }
        end
      end
      hash
    end

    sig { override.params(request: ExemptionRequest).returns(String) }
    def permalink(request)
      T.must(SecretScanning::BypassDelegation.secret_scanning_bypass_url(request))
    end
  end
end
