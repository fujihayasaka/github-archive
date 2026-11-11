# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::AutomaticBaseChangeEventAdapter < PullRequest::Adapter::IssueEventAdapter
  AUTOMATIC_BASE_CHANGE_SUCCEEDED_EVENT = "AutomaticBaseChangeSucceededEvent"
  AUTOMATIC_BASE_CHANGE_FAILED_EVENT = "AutomaticBaseChangeFailedEvent"

  attr_reader :action

  def initialize(context, event_id:, action:)
    super(context, event_id: event_id)
    @action = action
  end
end
