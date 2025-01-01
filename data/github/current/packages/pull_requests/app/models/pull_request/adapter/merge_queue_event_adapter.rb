# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::MergeQueueEventAdapter < PullRequest::Adapter::IssueEventAdapter
  ADDED_TO_MERGE_QUEUE_EVENT = "AddedToMergeQueueEvent"
  REMOVED_FROM_MERGE_QUEUE_EVENT = "RemovedFromMergeQueueEvent"

  attr_reader :issue_event, :pull_request

  def initialize(context, event_id:)
    super(context, event_id: event_id)
    @pull_request = context.pull_request
  end
end
