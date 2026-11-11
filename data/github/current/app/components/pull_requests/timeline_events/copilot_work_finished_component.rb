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
      return "Copilot" if ::Apps::Privileged.integration(:copilot_pull_request_reviewer)&.id == @issue_event.performed_by_integration_id

      agent = ::AgenticApp.agent_for_integration_id(@issue_event.performed_by_integration_id)
      return "Unknown" if agent.nil?

      agent.display_name
    end

    memoize def session_url
      return nil unless @issue_event.source_id.present?
      return nil unless respond_to?(:copilot_agent_task_url)

      copilot_agent_task_url(global_id: @pull_request.global_relay_id, session_id: @issue_event.source_id)
    end

    private

    def action_phrase
      return "finished reviewing" if performed_by_code_review_agent?(issue_event)
      "finished work"
    end
  end
end
