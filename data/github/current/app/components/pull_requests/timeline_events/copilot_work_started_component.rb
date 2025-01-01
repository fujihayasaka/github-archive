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
  end
end
