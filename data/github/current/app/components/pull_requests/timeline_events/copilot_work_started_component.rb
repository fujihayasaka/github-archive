# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class CopilotWorkStartedComponent < ApplicationComponent
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

    memoize def session_url
      return nil unless @issue_event.source_id.present?

      if FeatureFlag.vexi.enabled?(:copilot_mission_control_link_to_sessions_in_repo, current_user, default: false)
        repo_agents_task_url(user_id: @repository.owner_display_login, repository: @repository.name, pull_number: @pull_request.number, session_id: @issue_event.source_id)
      elsif respond_to?(:copilot_agent_task_url)
        copilot_agent_task_url(global_id: @pull_request.global_relay_id, session_id: @issue_event.source_id)
      end
    end

    def trigger_source
      return nil unless FeatureFlag.vexi.enabled?("copilot_swe_agent_timeline_trigger_source", current_user, default: false) && @issue_event.trigger_source_type.present? && @issue_event.trigger_source_url.present?
      {
        text: readable_trigger_source_type,
        url: @issue_event.trigger_source_url
      }
    end

    def agent_name
      return "Copilot" unless FeatureFlag.vexi.enabled?(:agentic_view_session, current_user, default: false)
      return "Copilot" if ::Apps::Privileged.integration(:copilot_pull_request_reviewer)&.id == @issue_event.performed_by_integration_id

      agent = ::AgenticApp.agent_for_integration_id(@issue_event.performed_by_integration_id)
      return "Unknown" if agent.nil?

      agent.display_name
    end

    private

    def view_session_data_attrs
      return unless performed_by_code_review_agent?(issue_event)
      payload = {
        session_id: @issue_event.source_id,
        organization_id: @repository.owner.id,
        repository_id: @repository.id,
        pull_request_id: @pull_request.id,
        user_analytics_tracking_id: current_user&.analytics_tracking_id
      }
      hydro_click_tracking_attributes("copilot.reviews.v0.ViewSession", payload)
    end

    def action_phrase
      return "started reviewing" if performed_by_code_review_agent?(issue_event)
      return "created this pull request from a session" if @issue_event.trigger_source_type == HydroSweAgentTimelineEventJob::TRIGGER_SOURCE_TYPE_PR_CREATED_FROM_SESSION
      "started work"
    end

    def readable_trigger_source_type
      case @issue_event.trigger_source_type
      when "issue_assignment"
        "issue assignment"
      when "pull_request_comment"
        "comment"
      when "pull_request_review"
        "review"
      else
        @issue_event.trigger_source_type.to_s.humanize.downcase # Fallback to humanize for unknown types
      end
    end
  end
end
