# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class CopilotWorkFinishedFailureComponent < ApplicationComponent
    attr_reader :issue_event, :pull_request

    def initialize(issue_event:, pull_request:)
      @issue_event = issue_event
      @pull_request = pull_request
      @repository = pull_request.repository
    end

    def render?
      @repository.copilot_swe_agent_enabled?(current_user)
    end

    memoize def session_path
      return nil unless @issue_event.source_id.present?
      repo_agent_session_path(user_id: @repository.owner_display_login, repository: @repository.name, pull_number: @pull_request.number, session_id: @issue_event.source_id)
    end

    def error_message
      issue_event.message.presence || "An unexpected error occurred. For more details, see the detailed logs in GitHub Actions."
    end
  end
end
