# typed: true
# frozen_string_literal: true

# This is a union type of both the connected and disconnected events.
class Issue::Adapter::BaseConnectEventAdapter < Issue::Adapter::IssueEventAdapter
  CONNECTED_EVENT = "ConnectedEvent"
  DISCONNECTED_EVENT = "DisconnectedEvent"

  attr_reader :is_cross_repository
  attr_reader :subject

  def initialize(context, event_id:, event_name:)
    super(context, event_id: event_id, event_name: event_name)

    @is_cross_repository = @issue_event.cross_subject_repository?

    subject = @issue_event.subject_as_issue_or_pull_request

    @subject = if subject.is_a?(Issue)
      Issue::Adapter::CrossReferenceSourceIssueAdapter.new(@context, issue: subject)
    elsif subject.is_a?(PullRequest)
      Issue::Adapter::CrossReferenceSourcePullRequestAdapter.new(@context, pull_request: subject)
    end
  end

  def is_cross_repository?
    @is_cross_repository
  end
end
