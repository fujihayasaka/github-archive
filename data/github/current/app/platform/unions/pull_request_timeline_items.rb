# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class PullRequestTimelineItems < Platform::Unions::Base
      description "An item in a pull request timeline"

      T.unsafe(self).possible_types(
        Objects::PullRequestCommit,
        Objects::PullRequestCommitCommentThread,
        Objects::PullRequestReview,
        Objects::PullRequestReviewThread,
        Objects::PullRequestRevisionMarker,

        # Pull request-specific event types (alphabetical)
        Objects::AddedToMergeQueueEvent,
        Objects::AutomaticBaseChangeFailedEvent,
        Objects::AutomaticBaseChangeSucceededEvent,
        Objects::AutoMergeDisabledEvent,
        Objects::AutoMergeEnabledEvent,
        Objects::AutoRebaseEnabledEvent,
        Objects::AutoSquashEnabledEvent,
        Objects::BaseRefChangedEvent,
        Objects::BaseRefForcePushedEvent,
        Objects::BaseRefDeletedEvent,
        Objects::ConvertToDraftEvent,
        Objects::CopilotWorkFinishedEvent,
        Objects::CopilotWorkFinishedFailureEvent,
        Objects::CopilotWorkStartedEvent,
        Objects::DeployedEvent,
        Objects::DeploymentEnvironmentChangedEvent,
        Objects::HeadRefDeletedEvent,
        Objects::HeadRefForcePushedEvent,
        Objects::HeadRefRestoredEvent,
        Objects::MergedEvent,
        Objects::ReadyForReviewEvent,
        Objects::RemovedFromMergeQueueEvent,
        Objects::ReviewDismissedEvent,
        Objects::ReviewRequestedEvent,
        Objects::ReviewRequestRemovedEvent,

        # Issue types
        *Unions::IssueTimelineItems.possible_types,
      )
    end
  end
end
