# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    class CodingAgentBannerComponent < ApplicationComponent
      attr_reader :pull_request, :current_user, :current_repository

      def initialize(pull_request:, current_user:, current_repository:)
        @pull_request = pull_request
        @current_user = current_user
        @current_repository = current_repository
      end

      def render?
        # Basic prerequisites that apply to both scenarios
        return false unless current_repository&.writable_by?(current_user)
        return false unless current_repository&.copilot_swe_agent_enabled?(current_user)

        # Show banner if PR was authored by agent (default behavior)
        agent_authored = CopilotSweAgent::Helpers.authored_by_agent?(pull_request)

        # Show banner if the coding_agent_stack_prs feature flag is enabled
        stack_prs_flag_enabled = current_user&.feature_flag_enabled?(:coding_agent_stack_prs, default: false)

        agent_authored || stack_prs_flag_enabled
      end
    end
  end
end
