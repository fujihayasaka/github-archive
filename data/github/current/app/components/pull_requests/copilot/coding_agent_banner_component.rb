# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    class CodingAgentBannerComponent < ApplicationComponent
      include ApplicationComponent::Rescuable
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

        # Don't show banner if PR was authored by Claude or Codex
        return false if authored_by_third_party_agent?

        # Show banner if PR was authored by agent (default behavior)
        agent_authored = CopilotSweAgent::Helpers.authored_by_agent?(pull_request)

        # Show banner if the coding_agent_stack_prs feature flag is enabled
        stack_prs_flag_enabled = current_user&.feature_flag_enabled?(:coding_agent_stack_prs, default: false)

        agent_authored || stack_prs_flag_enabled
      end

      private

      def authored_by_third_party_agent?
        return false unless pull_request&.user.is_a?(::Bot)

        bot_user = pull_request.user
        integration = bot_user.integration
        return false if integration.nil?

        agent = AgenticApp.agent_for_integration_id(integration.id)
        agent.present? && !agent.global?
      end
    end
  end
end
