# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::CatchUpSnapshot
  class Payload
    class TimelineUser < T::Struct
      const :id, Integer
      const :login, String
      const :avatarUrl, String
    end

    class TimelineEvent < T::Struct
      const :timestamp, String
      const :user, TimelineUser
      const :additionalInfo, T.nilable(T::Hash[Symbol, T.untyped]), default: nil
    end

    class TimelineEventCollection < T::Struct
      const :count, Integer
      const :events, T::Array[TimelineEvent]
    end

    class TimelineSummary < T::Struct
      const :approvals, TimelineEventCollection
      const :changesRequested, TimelineEventCollection
      const :comments, TimelineEventCollection
      const :reviewComments, TimelineEventCollection
      const :issueComments, TimelineEventCollection
      const :commits, TimelineEventCollection
      const :closed, TimelineEventCollection
      const :reopened, TimelineEventCollection
      const :markedAsDraft, TimelineEventCollection
      const :readyForReview, TimelineEventCollection
      const :labeled, TimelineEventCollection
      const :reviewRequested, TimelineEventCollection
      const :forcePushed, TimelineEventCollection
      const :merged, TimelineEventCollection
      const :baseChanged, TimelineEventCollection
      const :baseChangeFailed, TimelineEventCollection
      const :descriptionUpdated, TimelineEventCollection
      const :total, Integer
    end

    TimelineItemPayload = PullRequests::PageData::TimelineEvents::Payload::TimelineItemPayload

    class Snapshot < T::Struct
      # Deprecated: prefer `timeline`. `summary` will be removed once
      # consumers have migrated to the ordered timeline list below.
      const :summary, TimelineSummary
      # Single ordered timeline using the shared timeline event payload,
      # matching the shape emitted by `PullRequests::PageData::TimelineEvents::Payload`.
      const :timeline, T::Array[TimelineItemPayload]
    end

    sig do
      params(
        data: PullRequests::PageData::CatchUpSnapshot::Loader::CatchUpSnapshotData
      ).returns(Snapshot)
    end
    def self.call(data)
      new.call(data)
    end

    sig do
      params(
        data: PullRequests::PageData::CatchUpSnapshot::Loader::CatchUpSnapshotData
      ).returns(Snapshot)
    end
    def call(data)
      Snapshot.new(
        summary: convert_summary(data.summary),
        timeline: convert_timeline(data.summary)
      )
    end

    private

    sig do
      params(
        summary: PullRequests::PageData::CatchUpSnapshot::Loader::Summary
      ).returns(T::Array[TimelineItemPayload])
    end
    def convert_timeline(summary)
      PullRequests::PageData::TimelineEvents::Payload.call(summary.events)
    end

    sig do
      params(
        summary: PullRequests::PageData::CatchUpSnapshot::Loader::Summary
      ).returns(TimelineSummary)
    end
    def convert_summary(summary)
      # Categorize events from the flat list
      approvals = []
      changes_requested = []
      comments = []
      review_comments = []
      issue_comments = []
      commits = []
      closed = []
      reopened = []
      marked_as_draft = []
      ready_for_review = []
      labeled = []
      review_requested = []
      force_pushed = []
      merged = []
      base_changed = []
      description_updated = []
      total = 0

      summary.events.each do |event|
        # Skip events without timestamp or user (can't be displayed)
        timestamp = event.timestamp
        user = event.user
        next unless timestamp && user

        total += 1
        payload_event = TimelineEvent.new(
          timestamp: timestamp.iso8601,
          user: TimelineUser.new(
            id: user.id,
            login: user.display_login,
            avatarUrl: user.avatar_url
          ),
          additionalInfo: event.additional_info
        )

        case event.type
        when "PullRequestReview"
          state = event.additional_info[:state]
          case state
          when :approved
            approvals << payload_event
          when :changes_requested
            changes_requested << payload_event
          when :commented
            comments << payload_event
          end
        when "PullRequestReviewThread"
          review_comments << payload_event
        when "IssueComment"
          issue_comments << payload_event
        when "PullRequestCommit"
          commits << payload_event
        when "IssueEvent"
          event_type = event.additional_info[:eventType]
          case event_type
          when "closed"
            closed << payload_event
          when "reopened"
            reopened << payload_event
          when "convert_to_draft"
            marked_as_draft << payload_event
          when "ready_for_review"
            ready_for_review << payload_event
          when "labeled", "unlabeled"
            labeled << payload_event
          when "review_requested", "review_request_removed"
            review_requested << payload_event
          when "merged"
            merged << payload_event
          when "head_ref_force_pushed", "base_ref_force_pushed"
            force_pushed << payload_event
          when "base_ref_changed"
            base_changed << payload_event
          end
        when "IssueEdit"
          description_updated << payload_event
        end
      end

      TimelineSummary.new(
        approvals: TimelineEventCollection.new(count: approvals.size, events: approvals),
        changesRequested: TimelineEventCollection.new(count: changes_requested.size, events: changes_requested),
        comments: TimelineEventCollection.new(count: comments.size, events: comments),
        reviewComments: TimelineEventCollection.new(count: review_comments.size, events: review_comments),
        issueComments: TimelineEventCollection.new(count: issue_comments.size, events: issue_comments),
        commits: TimelineEventCollection.new(count: commits.size, events: commits),
        closed: TimelineEventCollection.new(count: closed.size, events: closed),
        reopened: TimelineEventCollection.new(count: reopened.size, events: reopened),
        markedAsDraft: TimelineEventCollection.new(count: marked_as_draft.size, events: marked_as_draft),
        readyForReview: TimelineEventCollection.new(count: ready_for_review.size, events: ready_for_review),
        labeled: TimelineEventCollection.new(count: labeled.size, events: labeled),
        reviewRequested: TimelineEventCollection.new(count: review_requested.size, events: review_requested),
        forcePushed: TimelineEventCollection.new(count: force_pushed.size, events: force_pushed),
        merged: TimelineEventCollection.new(count: merged.size, events: merged),
        baseChanged: TimelineEventCollection.new(count: base_changed.size, events: base_changed),
        baseChangeFailed: TimelineEventCollection.new(count: 0, events: []),
        descriptionUpdated: TimelineEventCollection.new(count: description_updated.size, events: description_updated),
        total: total
      )
    end
  end
end
