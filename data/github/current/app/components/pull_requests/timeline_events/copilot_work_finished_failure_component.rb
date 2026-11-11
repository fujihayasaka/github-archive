# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class CopilotWorkFinishedFailureComponent < ApplicationComponent
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

    memoize def session_path
      return nil unless @issue_event.source_id.present?
      return nil unless respond_to?(:copilot_agent_task_path)

      copilot_agent_task_path(global_id: @pull_request.global_relay_id, session_id: @issue_event.source_id)
    end

    def error_message
      issue_event.message.presence || "An unexpected error occurred. For more details, see the detailed logs in GitHub Actions."
    end

    private

    def action_phrase
      return "stopped reviewing" if performed_by_code_review_agent?(issue_event)
      "stopped work"
    end
  end
end
