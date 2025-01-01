# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::CopilotWorkFinishedEventAdapter < PullRequest::Adapter::IssueEventAdapter
  COPILOT_WORK_FINISHED_EVENT = "CopilotWorkFinishedEvent"

  attr_reader :pull_request

  def initialize(context, event_id:)
    super(context, event_id: event_id)
    @pull_request = context.pull_request
  end
end
