# typed: strict
# frozen_string_literal: true

module Exemptions
  class Evaluators::SecretScanningBypass < ExemptionEvaluator
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
      reviewers_source = T.must(request.repository)
      bypass_reviewers, error_message = SecretScanning::Services::DelegatedBypassService.get_bypass_reviewers(reviewers_source, T.must(request.requester&.id))
      return [] if bypass_reviewers.nil? || bypass_reviewers.empty? || error_message

      user_ids, team_ids, role_ids = SecretScanning::Services::DelegatedBypassService.split_bypass_reviewers_ids_by_type(bypass_reviewers, reviewers_source)

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

      # CLI pushes and web pushes have slightly different structures
      # CLI push
      if rule_run&.insights_ui_metadata&.keys&.include?("secrets")
        matching_secrets = rule_run.insights_ui_metadata["secrets"].filter { |secret| secret["bypass_placeholder_ksuid"] == request.resource_identifier }
        matching_secrets.each do |secret|
          hash[:data] << {
            secret_type: secret["token_metadata"]["label"],
            locations: secret["locations"].map do |location|
              {
                branch: request.resource_owner.ref_name,
                commit: location["commit_oid"],
                path: "#{location["path"]}:#{location["start_line"]}:#{location["start_line_byte_position"]}",
              }
            end
          }
        end
      # Web push
      elsif rule_run&.insights_ui_metadata&.keys&.length && rule_run&.insights_ui_metadata&.keys&.length > 0
        path = rule_run.insights_ui_metadata.keys.first
        matching_secrets = rule_run.insights_ui_metadata[path]["secrets"].filter { |secret| secret["bypass_placeholder_ksuid"] == request.resource_identifier }
        matching_secrets.each do |secret|
          hash[:data] << {
            secret_type: secret["token_metadata"]["label"],
            locations: secret["locations"].map do |location|
              {
                branch: request.resource_owner.ref_name,
                commit: "Pending (from file editor)",
                path: "#{path}:#{location["start_line"]}:#{location["start_line_byte_position"]}",
              }
            end
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
