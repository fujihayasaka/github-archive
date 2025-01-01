# typed: true
# frozen_string_literal: true

module IssueEventsHelper
  EVENT_ICONS = {
    "labeled"                      => "tag",
    "unlabeled"                    => "tag",
    "milestoned"                   => "milestone",
    "demilestoned"                 => "milestone",
    "issue_closed"                 => "issue-closed",
    "issue_closed_not_planned"     => Issue::StateReasonDependency::OCTICONS[:not_planned][:icon],
    "pr_closed"                    => "git-pull-request-closed",
    "merged"                       => "git-merge",
    "assigned"                     => "person",
    "unassigned"                   => "person",
    "review_requested"             => "eye",
    "review_request_removed"       => "x",
    "head_ref_deleted"             => "git-branch",
    "head_ref_restored"            => "git-branch",
    "renamed"                      => "pencil",
    "locked"                       => "lock",
    "unlocked"                     => "key",
    "base_ref_force_pushed"        => "repo-push",
    "head_ref_force_pushed"        => "repo-push",
    "signoff"                      => "thumbsup",
    "signoff_canceled"             => "dash",
    "base_ref_changed"             => "git-branch",
    "base_ref_deleted"             => "git-branch",
    "added_to_project"             => "project",
    "moved_columns_in_project"     => "project",
    "removed_from_project"         => "project",
    "converted_note_to_issue"      => "project",
    "comment_deleted"              => "x",
    "marked_as_duplicate"          => "bookmark",
    "unmarked_as_duplicate"        => "bookmark",
    "ready_for_review"             => "eye",
    "pinned"                       => "pin",
    "unpinned"                     => "pin",
    "convert_to_draft"             => "git-pull-request-draft",
    "transferred"                  => "arrow-right",
    "pr_reopened"                  => "git-pull-request",
    "issue_reopened"               => "issue-reopened",
    "converted_to_discussion"      => "comment-discussion",
    "added_to_project_v2"          => "table",
    "removed_from_project_v2"      => "table",
    "project_v2_item_status_changed" => "table",
    "converted_from_draft" => "issue-draft",
  }
  EVENT_ICONS.default = "dot-fill"
  EVENT_ICONS.freeze

  ROLLUP_TIME_WINDOW = 7.days

  def icon_for_event(event, subject_type = nil, reason = nil)
    if subject_type == :pull_request
      EVENT_ICONS["pr_#{event}"]
    elsif subject_type == :issue
      key = "issue_#{event}"
      key = "#{key}_#{reason}" if reason
      EVENT_ICONS[key]
    else
      EVENT_ICONS[event]
    end
  end

  # Requires: EventsCanRollup on nodes
  def rollup_issue_event_nodes(nodes)
    comparison_event = nodes.first
    nodes.chunk_while do |_node_before, node_after|
      events_can_rollup?(event: node_after, comparison_event: comparison_event).tap do |can_rollup|
        comparison_event = node_after unless can_rollup
      end
    end.to_a
  end

  def events_can_rollup?(event:, comparison_event:)
    # Events must be able to be rolled up
    return false unless perform_rollup_for_event_type?(event)

    # Events must have the same rollup key
    return false unless event_type_rollup_key(event) == event_type_rollup_key(comparison_event)

    # Events must have the same actor
    return false unless event.actor&.login == comparison_event.actor&.login

    # Events must have been triggered via the same integration
    if performable_via_app?(event) && performable_via_app?(comparison_event)
      return false unless event.via_app&.id == comparison_event.via_app&.id
    end

    # Events need to be within a week of each other.
    return false unless (event.created_at - comparison_event.created_at).abs < ROLLUP_TIME_WINDOW.to_i

    # Event specific details allow rolling up
    return false unless perform_event_type_specific_rollup?(
      event: event, comparison_event: comparison_event,
    )

    true
  end

  def performable_via_app?(event)
    event.is_a?(PullRequest::Adapter::IssueEventAdapter) || event.is_a?(Issue::Adapter::IssueEventAdapter)
  end

  # Platform type => rollup key
  EVENT_ROLLUP_TYPES = {
    "Issue::Adapter::LabeledEventAdapter" => :label,
    "Issue::Adapter::UnlabeledEventAdapter" => :label,
    "Issue::Adapter::AssignedEventAdapter" => :assignment,
    "Issue::Adapter::UnassignedEventAdapter" => :assignment,
    "PullRequest::Adapter::ReviewRequestedEventAdapter" => :review_request,
    "PullRequest::Adapter::ReviewRequestRemovedEventAdapter" => :review_request,
    "PullRequest::Adapter::ReviewDismissedEventAdapter" => :review_dismissal,
    "Issue::Adapter::MilestonedEventAdapter" => :milestone,
    "Issue::Adapter::DemilestonedEventAdapter" => :milestone,
    "Issue::Adapter::MilestoneEventAdapter" => :milestone,
    "Issue::Adapter::MarkedAsDuplicateEventAdapter" => :duplicate,
    "Issue::Adapter::UnmarkedAsDuplicateEventAdapter" => :duplicate,
    "Issue::Adapter::CrossReferencedEventAdapter" => :cross_reference,
    "PullRequest::Adapter::HeadRefForcePushedEventAdapter" => :head_ref_force_push,
    "PullRequest::Adapter::BaseRefForcePushedEventAdapter" => :base_ref_force_push,
    "Issue::Adapter::ConnectedEventAdapter" => :connected,
    "Issue::Adapter::DisconnectedEventAdapter" => :disconnected,
    "Issue::Adapter::AddedToMemexProjectEventAdapter" => :added_to_memex_project,
  }.freeze

  def perform_rollup_for_event_type?(event)
    event_type_rollup_key(event)
  end

  def event_type_rollup_key(event)
    EVENT_ROLLUP_TYPES[event.class.name]
  end

  def perform_event_type_specific_rollup?(event:, comparison_event:)
    case comparison_event
    when PullRequest::Adapter::ReviewDismissedEventAdapter
      event.issue_event.after_commit_oid == comparison_event.issue_event.after_commit_oid
    when Issue::Adapter::MarkedAsDuplicateEventAdapter, Issue::Adapter::UnmarkedAsDuplicateEventAdapter
      event.canonical&.id == comparison_event.canonical&.id
    when PullRequest::Adapter::ReviewRequestedEventAdapter
      issue_event = event.issue_event
      comparison_issue_event = comparison_event.issue_event

      comparison_code_owners_file_id = comparison_issue_event.review_request&.async_codeowners_file&.sync&.global_relay_id

      # Review requests with code owners file should only be rolled up with other review
      # requests (and not review request removals) pointing to the same code owners file.
      if comparison_code_owners_file_id
        issue_event.event == "review_requested" && comparison_code_owners_file_id == issue_event.review_request&.async_codeowners_file&.sync&.global_relay_id
      elsif issue_event.event == "review_requested"
        !issue_event.review_request&.async_codeowners_file&.sync&.global_relay_id
      else
        true
      end
    when PullRequest::Adapter::ReviewRequestRemovedEventAdapter
      if event.is_a?(PullRequest::Adapter::ReviewRequestedEventAdapter)
        !event.issue_event.review_request&.async_codeowners_file&.sync
      else
        true
      end
    else
      true
    end
  end
end
