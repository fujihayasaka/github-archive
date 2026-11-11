# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class CopilotWorkFinishedComponent < ApplicationComponent
    include PullRequests::CopilotTimelineEventsHelper

    attr_reader :issue_event, :pull_request

    def initialize(issue_event:, pull_request:)
      @issue_event = issue_event
      @pull_request = pull_request
      @repository = pull_request.repository
    end

    def render?
      return @repository.copilot_swe_agent_enabled?(current_user) if performed_by_coding_agent?(issue_event)
      performed_by_code_review_agent?(issue_event)
    end

    def agent_name
      return "Copilot" unless FeatureFlag.vexi.enabled?(:agentic_view_session, current_user, default: false)
      ccr_id = if FeatureFlag.vexi.enabled?(:agentic_app_lookup_optimization, default: false)
        ::Apps::Privileged::Registry.app_id(app_alias: :copilot_pull_request_reviewer, type: "Integration")
      else
        ::Apps::Privileged.integration(:copilot_pull_request_reviewer)&.id
      end
      return "Copilot" if ccr_id == @issue_event.performed_by_integration_id

      agent = ::AgenticApp.agent_for_integration_id(@issue_event.performed_by_integration_id)
      return "Unknown" if agent.nil?

      agent.display_name
    end

    memoize def session_url
      return nil unless @issue_event.source_id.present?

      if FeatureFlag.vexi.enabled?(:copilot_mission_control_session_redirect_links, current_user, default: false)
        return nil unless respond_to?(:repo_session_url)
        repo_session_url(user_id: @repository.owner_display_login, repository: @repository.name, session_id: @issue_event.source_id)
      else
        return nil unless respond_to?(:repo_agents_task_url)
        repo_agents_task_url(user_id: @repository.owner_display_login, repository: @repository.name, pull_number: @pull_request.number, session_id: @issue_event.source_id)
      end
    end

    private

    def action_phrase
      return "finished reviewing" if performed_by_code_review_agent?(issue_event)
      "finished work"
    end
  end
end
