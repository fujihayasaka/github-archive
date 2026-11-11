# typed: true
# frozen_string_literal: true

class Issue::Adapter::DuplicateEventAdapter < Issue::Adapter::IssueEventAdapter
  MARKED_AS_DUPLICATE_EVENT = "MarkedAsDuplicateEvent"
  UNMARKED_AS_DUPLICATE_EVENT = "UnmarkedAsDuplicateEvent"

  attr_reader :canonical
  attr_reader :is_cross_repository

  def initialize(context, event_id:, event_name:)
    super(context, event_id: event_id, event_name: event_name)

    @is_cross_repository = @issue_event.cross_subject_repository?
    subject = @issue_event.subject
    @canonical = if subject.is_a?(Issue)
      Issue::Adapter::DuplicateIssueAdapter.new(@context, issue: subject)
    elsif subject.is_a?(PullRequest)
      Issue::Adapter::DuplicatePullRequestAdapter.new(@context, pull_request: subject)
    end
  end

  def is_cross_repository?
    @is_cross_repository
  end
end
