# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class IssueTimelineItem < Platform::Unions::Base
      description "An item in an issue timeline"

      possible_types(
        Objects::Commit,
        Objects::IssueComment,
        Objects::CrossReferencedEvent,
        Objects::ClosedEvent,
        Objects::ReopenedEvent,
        Objects::SubscribedEvent,
        Objects::UnsubscribedEvent,
        Objects::ReferencedEvent,
        Objects::AssignedEvent,
        Objects::UnassignedEvent,
        Objects::LabeledEvent,
        Objects::UnlabeledEvent,
        Objects::UserBlockedEvent,
        Objects::MilestonedEvent,
        Objects::DemilestonedEvent,
        Objects::RenamedTitleEvent,
        Objects::LockedEvent,
        Objects::UnlockedEvent,
        Objects::TransferredEvent,
      )
    end
  end
end
