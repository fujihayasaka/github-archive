# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::BaseRefChangedEventAdapter < PullRequest::Adapter::IssueEventAdapter
  BASE_REF_CHANGED_EVENT = "BaseRefChangedEvent"

  attr_reader :pull_request

  def initialize(context, event_id:)
    super(context, event_id: event_id)

    @pull_request = context.pull_request
  end
end
