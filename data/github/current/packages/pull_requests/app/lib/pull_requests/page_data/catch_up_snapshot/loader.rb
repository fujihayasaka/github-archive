# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::CatchUpSnapshot
  class Loader
    class Summary < T::Struct
      const :events, T::Array[PullRequests::PageData::TimelineEvents::Loader::Event]
    end

    class CatchUpSnapshotData < T::Struct
      const :pull_request, PullRequest
      const :summary, Summary
    end

    sig do
      params(
        pull_request: PullRequest,
        current_user: T.nilable(User),
        since_timestamp: Time
      ).returns(CatchUpSnapshotData)
    end
    def self.load(pull_request:, current_user:, since_timestamp:)
      new(pull_request: pull_request, current_user: current_user, since_timestamp: since_timestamp).load
    end

    sig do
      params(
        pull_request: PullRequest,
        current_user: T.nilable(User),
        since_timestamp: Time
      ).void
    end
    def initialize(pull_request:, current_user:, since_timestamp:)
      @pull_request = pull_request
      @current_user = current_user
      @since_timestamp = since_timestamp
      @event_loader = T.let(
        PullRequests::PageData::TimelineEvents::Loader.new(current_user: current_user, pull_request: pull_request),
        PullRequests::PageData::TimelineEvents::Loader
      )
    end

    sig { returns(CatchUpSnapshotData) }
    def load
      # Load filtered items using the since filter
      # If there's no since_timestamp, show no events to the user
      new_items = load_timeline_items(since_timestamp: @since_timestamp)

      # Load description updates separately (not part of timeline)
      description_edits = load_description_updates(since_timestamp: @since_timestamp)

      summary = build_summary(new_items, description_edits)

      CatchUpSnapshotData.new(
        pull_request: @pull_request,
        summary: summary
      )
    end

    private

    sig { params(since_timestamp: Time).returns(T::Array[T.untyped]) }
    def load_timeline_items(since_timestamp:)
      # Load timeline data with optional since filter
      filter_options = {
        since: since_timestamp
      }

      timeline = PullRequests::Timeline::PullRequestTimeline.for(
        @pull_request,
        @current_user,
        filter_options
      )

      # Load timeline placeholders and values
      Platform::Security::RepositoryAccess.with_viewer(@current_user) do
        timeline.legacy_timeline.async_values.sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end

    sig { params(since_timestamp: Time).returns(T::Array[T.untyped]) }
    def load_description_updates(since_timestamp:)
      # Load user content edits for the issue (description updates)
      # PullRequest has an associated Issue where the body is stored
      issue = @pull_request.issue
      return [] unless issue && issue.viewer_can_read_user_content_edits?(@current_user)

      # Get edits that happened after the since_timestamp
      # Skip the first edit (creation) if it exists
      edits = issue.user_content_edits
        .includes(:editor)
        .where("edited_at > ?", since_timestamp)
        .order(edited_at: :asc)
        .to_a # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      # Filter out the initial creation edit (if present)
      edits.reject.with_index { |edit, index| index == edits.size - 1 && edit.first_edit? }
    end

    sig { params(items: T::Array[T.untyped], description_edits: T::Array[T.untyped]).returns(Summary) }
    def build_summary(items, description_edits = [])
      # Load all items in batch (preloading handled internally)
      all_items = items + description_edits
      Summary.new(events: @event_loader.load(all_items))
    end
  end
end
