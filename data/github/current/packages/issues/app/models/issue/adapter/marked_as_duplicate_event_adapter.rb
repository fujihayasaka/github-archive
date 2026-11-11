# typed: true
# frozen_string_literal: true

class Issue::Adapter::MarkedAsDuplicateEventAdapter < Issue::Adapter::DuplicateEventAdapter
  TYPES = [PlatformTypes::MarkedAsDuplicateEvent]

  attr_reader :viewer_can_undo
  attr_reader :unmark_as_duplicate_resource_path
  attr_reader :duplicate

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: MARKED_AS_DUPLICATE_EVENT)

    index = [@issue_event.issue_event_detail.subject_id, @issue_event.issue_id]
    duplicate_issue = @context.duplicate_issues_by_id[index]

    @viewer_can_undo = @issue_event.can_unmark_duplicate_issue_as_duplicate?(duplicate_issue, context.viewer)
    @unmark_as_duplicate_resource_path = @issue_event.unmark_as_duplicate_path_uri

    # TODO: this is not preloading the pull-request in case the issue has a pull_request_id
    duplicate = @issue_event.issue_or_pull_request
    @duplicate = if duplicate.is_a?(Issue)
      Issue::Adapter::DuplicateIssueAdapter.new(@context, issue: duplicate)
    elsif duplicate.is_a?(PullRequest)
      Issue::Adapter::DuplicatePullRequestAdapter.new(@context, pull_request: duplicate)
    end
  end

  def viewer_can_undo?
    @viewer_can_undo
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
