# typed: true
# frozen_string_literal: true

class Issue::Adapter::TimelinePageAdapter < Issue::Adapter::Base
  include GitHub::ResilienceMixin
  attr_reader :page_info
  attr_reader :nodes

  def initialize(context, issue_adapter:, timeline:, timeline_page:)
    super(context)

    entries = timeline_page&.async_entries&.sync || []

    @nodes = entries.map do |entry|
      case entry
      when IssueComment
        Issue::Adapter::CommentAdapter.new(context, comment_id: entry.id, issue_adapter: issue_adapter)
      when IssueEvent
        case entry.event
        when "labeled"
          Issue::Adapter::LabeledEventAdapter.new(context, event_id: entry.id)
        when "unlabeled"
          Issue::Adapter::UnlabeledEventAdapter.new(context, event_id: entry.id)
        when "assigned"
          Issue::Adapter::AssignedEventAdapter.new(context, event_id: entry.id)
        when "unassigned"
          Issue::Adapter::UnassignedEventAdapter.new(context, event_id: entry.id)
        when "comment_deleted"
          Issue::Adapter::CommentDeletedEventAdapter.new(context, event_id: entry.id)
        when "closed"
          Issue::Adapter::ClosedEventAdapter.new(context, event_id: entry.id)
        when "milestoned"
          Issue::Adapter::MilestonedEventAdapter.new(context, event_id: entry.id)
        when "demilestoned"
          Issue::Adapter::DemilestonedEventAdapter.new(context, event_id: entry.id)
        when "added_to_project"
          Issue::Adapter::AddedToProjectEventAdapter.new(context, event_id: entry.id)
        when "removed_from_project"
          Issue::Adapter::RemovedFromProjectEventAdapter.new(context, event_id: entry.id)
        when "moved_columns_in_project"
          Issue::Adapter::MovedColumnsInProjectEventAdapter.new(context, event_id: entry.id)
        when "converted_note_to_issue"
          Issue::Adapter::ConvertedNoteToIssueEventAdapter.new(context, event_id: entry.id)
        when "renamed"
          Issue::Adapter::RenameEventAdapter.new(context, event_id: entry.id)
        when "reopened"
          Issue::Adapter::ReopenedEventAdapter.new(context, event_id: entry.id)
        when "referenced"
          with_database_error_fallback(fallback: nil) do
            Issue::Adapter::ReferencedEventAdapter.new(context, event_id: entry.id)
          end
        when "marked_as_duplicate"
          Issue::Adapter::MarkedAsDuplicateEventAdapter.new(context, event_id: entry.id)
        when "unmarked_as_duplicate"
          Issue::Adapter::UnmarkedAsDuplicateEventAdapter.new(context, event_id: entry.id)
        when "locked"
          Issue::Adapter::LockedEventAdapter.new(context, event_id: entry.id)
        when "unlocked"
          Issue::Adapter::UnlockedEventAdapter.new(context, event_id: entry.id)
        when "transferred"
          Issue::Adapter::TransferredEventAdapter.new(context, event_id: entry.id)
        when "user_blocked"
          Issue::Adapter::UserBlockedEventAdapter.new(context, event_id: entry.id)
        when "pinned"
          Issue::Adapter::PinnedEventAdapter.new(context, event_id: entry.id)
        when "unpinned"
          Issue::Adapter::UnpinnedEventAdapter.new(context, event_id: entry.id)
        when "connected"
          Issue::Adapter::ConnectedEventAdapter.new(context, event_id: entry.id)
        when "disconnected"
          Issue::Adapter::DisconnectedEventAdapter.new(context, event_id: entry.id)
        when "converted_to_discussion"
          Issue::Adapter::ConvertedToDiscussionEventAdapter.new(context, event_id: entry.id)
        when "base_ref_changed"
          PullRequest::Adapter::BaseRefChangedEventAdapter.new(context, event_id: entry.id)
        when "base_ref_deleted"
          PullRequest::Adapter::BaseRefDeletedEventAdapter.new(context, event_id: entry.id)
        when "head_ref_deleted"
          PullRequest::Adapter::HeadRefDeletedOrRestoredEventAdapter.new(context, event_id: entry.id)
        when "head_ref_restored"
          PullRequest::Adapter::HeadRefDeletedOrRestoredEventAdapter.new(context, event_id: entry.id)
        when "merged"
          PullRequest::Adapter::MergedEventAdapter.new(context, event_id: entry.id)
        when "automatic_base_change_succeeded"
          PullRequest::Adapter::AutomaticBaseChangeEventAdapter.new(context, event_id: entry.id, action: :success)
        when "automatic_base_change_failed"
          PullRequest::Adapter::AutomaticBaseChangeEventAdapter.new(context, event_id: entry.id, action: :failure)
        when "review_dismissed"
          PullRequest::Adapter::ReviewDismissedEventAdapter.new(context, event_id: entry.id)
        when "review_requested"
          PullRequest::Adapter::ReviewRequestedEventAdapter.new(context, event_id: entry.id)
        when "review_request_removed"
          PullRequest::Adapter::ReviewRequestRemovedEventAdapter.new(context, event_id: entry.id)
        when "deployed"
          PullRequest::Adapter::DeployedEventAdapter.new(context, event_id: entry.id)
        when "deployment_environment_changed"
          PullRequest::Adapter::DeploymentEnvironmentChangedEventAdapter.new(context, event_id: entry.id)
        when "auto_merge_disabled"
          PullRequest::Adapter::AutoMergeEventAdapter.new(context, event_id: entry.id)
        when "auto_merge_enabled"
          PullRequest::Adapter::AutoMergeEventAdapter.new(context, event_id: entry.id)
        when "auto_squash_enabled"
          PullRequest::Adapter::AutoMergeEventAdapter.new(context, event_id: entry.id)
        when "auto_rebase_enabled"
          PullRequest::Adapter::AutoMergeEventAdapter.new(context, event_id: entry.id)
        when "ready_for_review"
          PullRequest::Adapter::ReadyForReviewEventAdapter.new(context, event_id: entry.id)
        when "convert_to_draft"
          PullRequest::Adapter::ConvertToDraftEventAdapter.new(context, event_id: entry.id)
        when "head_ref_force_pushed"
          PullRequest::Adapter::HeadRefForcePushedEventAdapter.new(context, event_id: entry.id)
        when "base_ref_force_pushed"
          PullRequest::Adapter::BaseRefForcePushedEventAdapter.new(context, event_id: entry.id)
        when "added_to_merge_queue"
          PullRequest::Adapter::MergeQueueEventAdapter.new(context, event_id: entry.id)
        when "removed_from_merge_queue"
          PullRequest::Adapter::MergeQueueEventAdapter.new(context, event_id: entry.id)
        end
      when Timeline::Placeholder::PullRequestCommit
        PullRequest::Adapter::CommitAdapter.new(context, commit_oid: entry.oid)
      when Timeline::Placeholder::PullRequestReview
        PullRequest::Adapter::PullRequestReviewAdapter.new(context, pull_request_review_id: entry.id)
      when Timeline::Placeholder::PullRequestReviewThread
        PullRequest::Adapter::LegacyPullRequestReviewThread.new(context, pull_request_review_thread_id: entry.database_id)
      when Timeline::Placeholder::PullRequestRevisionMarker
        PullRequest::Adapter::PullRequestRevisionMarkerAdapter.new(context, last_seen_commit_oid: entry.last_seen_commit_oid)
      when CrossReference
        Issue::Adapter::CrossReferencedEventAdapter.new(context, event_id: entry.id)
      when ::Timeline::Placeholder::AddedToMemexProject
        Issue::Adapter::AddedToMemexProjectEventAdapter.new(context, entry)
      when ::Timeline::Placeholder::RemovedFromMemexProject
        Issue::Adapter::RemovedFromMemexProjectEventAdapter.new(context, entry)
      when ::Timeline::Placeholder::ProjectItemStatusChanged
        Issue::Adapter::ProjectItemStatusChangedEventAdapter.new(context, entry)
      when ::Timeline::Placeholder::ConvertedFromDraft
        Issue::Adapter::ConvertedFromDraftEventAdapter.new(context, entry)
      else
        exception_message = "Entry #{entry.class} not implemented"
        if context.raise_on_missing_timeline_adapter
          raise exception_message
        else
          GitHub.logger.error(
            exception_message,
            "gh.issue_id" => context.issue.id,
            "gh.viewer_id" => context.viewer.id,
            "fn.class" => self.class.name,
            "fn.name" => __method__.to_s
          )

          nil
        end
      end
    end.compact

    # Replace invalid nodes with nil value.
    @nodes = @nodes.map { |n| n.invalid? ? nil : n }

    @page_info = Issue::Adapter::TimelinePageInfoAdapter.new(context, timeline_page: timeline_page)
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
