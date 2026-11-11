# typed: true
# frozen_string_literal: true

require "monolith-twirp-actions-core"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # Handler for the MonolithTwirp::Actions::Core::V1::RulesetsAPIService
      class RulesetsAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: %w[launch].freeze
        handles_service ::MonolithTwirp::Actions::Core::V1::RulesetsAPIService

        resolve_tenant_context do |req, _env|
          begin
            repo = Repositories::Public.find_active!(req.repository_id)
            next repo.owner&.business
          rescue ActiveRecord::RecordNotFound
            Twirp::Error.not_found("repository not found", argument: "repository_id")
          end
        end

        # Public: Implementation of the EvaluateActionsRuleset Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Actions::Core::V1::EvaluateActionsRulesetRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Actions::Core::V1::EvaluateActionsRulesetResponse, or a Twirp::Error.
        def evaluate_actions_ruleset(req, env)
          EvaluateActionsRuleset.call(req)
        end
      end
    end
  end
end
