# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class IssueTimelineItems < Unions::Base
      description "An item in an issue timeline"

      include Platform::Authorization::ReauthorizeScopedObjects

      possible_types(
        Objects::IssueComment,
        Objects::CrossReferencedEvent,
        # All event types (alphabetical)
        Objects::AddedToProjectEvent,
        Objects::AddedToProjectV2Event,
        Objects::AssignedEvent,
        Objects::ClosedEvent,
        Objects::CommentDeletedEvent,
        Objects::ConnectedEvent,
        Objects::ConvertedFromDraftEvent,
        Objects::ConvertedNoteToIssueEvent,
        Objects::ConvertedToDiscussionEvent,
        Objects::DemilestonedEvent,
        Objects::DisconnectedEvent,
        Objects::LabeledEvent,
        Objects::LockedEvent,
        Objects::MarkedAsDuplicateEvent,
        Objects::MentionedEvent,
        Objects::MilestonedEvent,
        Objects::MovedColumnsInProjectEvent,
        Objects::PinnedEvent,
        Objects::ProjectV2ItemStatusChangedEvent,
        Objects::ReferencedEvent,
        Objects::RemovedFromProjectEvent,
        Objects::RemovedFromProjectV2Event,
        Objects::RenamedTitleEvent,
        Objects::ReopenedEvent,
        Objects::SubscribedEvent,
        Objects::TransferredEvent,
        Objects::UnassignedEvent,
        Objects::UnlabeledEvent,
        Objects::UnlockedEvent,
        Objects::UserBlockedEvent,
        Objects::UnmarkedAsDuplicateEvent,
        Objects::UnpinnedEvent,
        Objects::UnsubscribedEvent,
      )
    end
  end
end
