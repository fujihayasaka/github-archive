# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Timeline
  class Loader
    include GitHub::ResilienceMixin
    include PullRequests::PageData::Telemetry

    MAX_PER_PAGE = 25
    PageInfo = PullRequests::PageData::Pagination::PageInfo
    Event = PullRequests::PageData::TimelineEvents::Loader::Event
    # All timeline item types this loader can render. Passed to PullRequestTimeline.for(...)
    # so the underlying query only fetches items we can handle — keeping cursor positions
    # accurate and preventing silent drops when filter_map runs.
    #
    # PullRequestCommitCommentThread is excluded because it is not rendered in the React
    # overview timeline and referencing its constant directly would violate Packwerk package
    # boundaries, so we filter by graphql_name instead.
    SUPPORTED_ITEM_TYPES = T.let(
      Platform::Unions::PullRequestTimelineItems.possible_types.reject { |item_type| item_type.graphql_name == "PullRequestCommitCommentThread" }.freeze,
      T::Array[T.class_of(Platform::Objects::Base)],
    )

    # Types that can be rendered in the React timeline UI. Used to drop entries
    # before they are passed to the event loader so we avoid preloading
    # associations and constructing Event structs for items the UI can't render.
    SUPPORTED_UI_TYPES = T.let(
      %w[
        IssueComment
        IssueEvent
        PullRequestReview
        PullRequestCommit
        CrossReference
        PullRequestReviewThread
        PullRequestRevisionMarker
      ].freeze,
      T::Array[String],
    )

    class PaginatedResult < T::Struct
      const :items, T::Array[Event]
      const :page_info, PageInfo

      sig { returns(PaginatedResult) }
      def self.empty
        new(
          items: [],
          page_info: PageInfo.empty
        )
      end
    end

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig { returns(T.nilable(User)) }
    attr_reader :current_user

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: PullRequest,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        after_cursor: T.nilable(String),
        per_page: Integer,
      ).returns(PaginatedResult)
    end
    def self.load(current_user:, pull_request:, cap_filter: nil, after_cursor: nil, per_page: MAX_PER_PAGE)
      new(
        current_user: current_user,
        pull_request: pull_request,
        cap_filter: cap_filter,
        after_cursor: after_cursor,
        per_page: per_page,
      ).load
    end

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: PullRequest,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        after_cursor: T.nilable(String),
        per_page: Integer,
      ).void
    end
    def initialize(current_user:, pull_request:, cap_filter: nil, after_cursor: nil, per_page: MAX_PER_PAGE)
      @current_user = current_user
      @pull_request = pull_request
      @cap_filter = cap_filter
      @after_cursor = after_cursor
      @per_page = per_page
    end

    sig { returns(PaginatedResult) }
    def load
      with_telemetry do
        with_database_error_fallback(fallback: PaginatedResult.empty) do
          timeline = PullRequests::Timeline::PullRequestTimeline.for(
            @pull_request,
            @current_user,
            {
              visible_events_only: true,
              filter_closed_if_preceded_by_merged: @pull_request.merged?,
              cap_filter: @cap_filter,
              item_types: SUPPORTED_ITEM_TYPES,
            }
          )

          timeline_page = timeline.get_page(first: @per_page, after_cursor: @after_cursor)

          entries = Platform::Security::RepositoryAccess.with_viewer(@current_user) do
            timeline_page.async_entries.sync
          end

          has_next = timeline_page.async_has_next_page.sync
          end_cursor = timeline_page.async_end_cursor.sync

          items = build_timeline_items(entries)

          PaginatedResult.new(
            items: items,
            page_info: PageInfo.new(
              has_next_page: has_next,
              cursor: end_cursor,
              page: 1,
            )
          )
        end
      end
    end

    private

    sig { params(entries: T::Array[T.untyped]).returns(T::Array[Event]) }
    def build_timeline_items(entries)
      supported_entries = entries.select { |entry| SUPPORTED_UI_TYPES.include?(entry.class.name&.demodulize) }
      event_loader = PullRequests::PageData::TimelineEvents::Loader.new(current_user: @current_user, pull_request: @pull_request)
      event_loader.load(supported_entries)
    end
  end
end
