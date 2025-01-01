# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class CopilotWorkStartedComponent < ApplicationComponent
    attr_reader :issue_event, :pull_request

    def initialize(issue_event:, pull_request:)
      @issue_event = issue_event
      @pull_request = pull_request
      @repository = pull_request.repository
    end

    def render?
      @repository.copilot_swe_agent_enabled?(current_user)
    end

    memoize def session_url
      return nil unless @issue_event.source_id.present?
      repo_agent_session_url(user_id: @repository.owner_display_login, repository: @repository.name, pull_number: @pull_request.number, session_id: @issue_event.source_id)
    end

    def trigger_source
      return nil unless FeatureFlag.vexi.enabled?("copilot_swe_agent_timeline_trigger_source", current_user, default: false) && @issue_event.trigger_source_type.present? && @issue_event.trigger_source_url.present?
      {
        text: readable_trigger_source_type,
        url: @issue_event.trigger_source_url
      }
    end

    private

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
