# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class PullRequestTimelineItem < Platform::Unions::Base
      description "An item in a pull request timeline"

      possible_types(
        Objects::Commit,
        Objects::CommitCommentThread,
        Objects::PullRequestReview,
        Objects::PullRequestReviewThread,
        Objects::PullRequestReviewComment,
        Objects::IssueComment,
        Objects::ClosedEvent,
        Objects::ReopenedEvent,
        Objects::SubscribedEvent,
        Objects::UnsubscribedEvent,
        Objects::MergedEvent,
        Objects::ReferencedEvent,
        Objects::CrossReferencedEvent,
        Objects::AssignedEvent,
        Objects::UnassignedEvent,
        Objects::LabeledEvent,
        Objects::UnlabeledEvent,
        Objects::MilestonedEvent,
        Objects::DemilestonedEvent,
        Objects::RenamedTitleEvent,
        Objects::LockedEvent,
        Objects::UnlockedEvent,
        Objects::DeployedEvent,
        Objects::DeploymentEnvironmentChangedEvent,
        Objects::HeadRefDeletedEvent,
        Objects::HeadRefRestoredEvent,
        Objects::HeadRefForcePushedEvent,
        Objects::BaseRefForcePushedEvent,
        Objects::BaseRefDeletedEvent,
        Objects::ReviewRequestedEvent,
        Objects::ReviewRequestRemovedEvent,
        Objects::ReviewDismissedEvent,
        Objects::UserBlockedEvent,
      )
    end
  end
end
