# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::CopilotWorkStartedEventAdapter < PullRequest::Adapter::IssueEventAdapter
  COPILOT_WORK_STARTED_EVENT = "CopilotWorkStartedEvent"

  attr_reader :pull_request

  def initialize(context, event_id:)
    super(context, event_id: event_id)
    @pull_request = context.pull_request
  end
end
