# typed: true
# frozen_string_literal: true

module PullRequests::TimelineEvents
  class CopilotWorkFinishedComponent < ApplicationComponent
    attr_reader :issue_event, :pull_request

    def initialize(issue_event:, pull_request:)
      @issue_event = issue_event
      @pull_request = pull_request
      @repository = pull_request.repository
    end

    def render?
      @repository.copilot_swe_agent_enabled?(current_user)
    end
  end
end
