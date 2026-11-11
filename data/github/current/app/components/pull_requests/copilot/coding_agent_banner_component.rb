# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    class CodingAgentBannerComponent < ApplicationComponent
      include ApplicationComponent::Rescuable
      include GitHub::ResilienceMixin
      rescue_from StandardError, with: :nothing
      attr_reader :pull_request, :current_user, :current_repository

      def initialize(pull_request:, current_user:, current_repository:)
        @pull_request = pull_request
        @current_user = current_user
        @current_repository = current_repository
      end

      def render?
        # Basic prerequisites that apply to all scenarios
        return false if pull_request&.closed?
        return false if pull_request&.cross_repo?
        return false unless current_repository&.writable_by?(current_user)
        return false unless current_repository&.copilot_swe_agent_enabled?(current_user)

        # Show banner if PR was authored by agent (default behavior)
        copilot_authored = CopilotSweAgent::Helpers.authored_by_agent?(pull_request)

        # Show banner if the coding_agent_stack_prs feature flag is enabled
        stack_prs_flag_enabled = current_user&.feature_flag_enabled?(:coding_agent_stack_prs, default: false)

        copilot_authored || authored_by_third_party_agent? || stack_prs_flag_enabled
      end

      private

      def authored_by_third_party_agent?
        return false unless pull_request&.user.is_a?(::Bot)

        bot_user = pull_request.user
        integration = bot_user.integration
        return false if integration.nil?

        with_database_error_fallback(fallback: false) do
          agent = AgenticApp.agent_for_integration_id(integration.id)
          agent.present? && !agent.global?
        end
      end

      def agent_mention_slug
        # fallback to "copilot" for cases where pull_request or user is nil
        return "copilot" unless pull_request&.user.is_a?(::Bot)

        bot_user = pull_request.user
        integration = bot_user.integration

        with_database_error_fallback(fallback: "copilot") do
          agent = AgenticApp.agent_for_integration_id(integration.id) || AgenticApp::CopilotAgent.instance
          AgenticApp.mention_token(agent)
        end
      end
    end
  end
end
