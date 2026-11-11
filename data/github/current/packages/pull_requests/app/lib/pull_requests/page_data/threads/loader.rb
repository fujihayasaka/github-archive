# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Threads
  class Loader
    include GitHub::ResilienceMixin
    include PullRequests::PageData::Telemetry

    PageInfo = PullRequests::PageData::Pagination::PageInfo

    class PullRequestThreadData < T::Struct
      const :id, Numeric
      const :subject_type, String
      const :is_resolved, T::Boolean
      const :resolved_by, T.nilable(User)
      const :viewer_can_reply, T::Boolean
      const :thread_comments, T::Array[PullRequests::PageData::ThreadComments::Loader::Comment]
      const :review_comments_limit, Integer
      const :review_comments_limit_exceeded, T::Boolean
    end

    class PaginatedResult < T::Struct
      const :items, T::Array[PullRequestThreadData]
      const :page_info, PageInfo

      sig { params(page: Integer).returns(PaginatedResult) }
      def self.empty(page: 1)
        new(
          items: [],
          page_info: PageInfo.empty(page: page)
        )
      end
    end

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig { returns(T.nilable(User)) }
    attr_reader :current_user

    sig { returns(PullRequests::PageData::Files::PageLimitConfig) }
    attr_reader :limit_config

    sig { returns(T.nilable(ConditionalAccess::Web::Filter)) }
    attr_reader :cap_filter

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: PullRequest,
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
      ).returns(PaginatedResult)
    end
    def self.load_initial_page(current_user:, pull_request:, limit_config:, cap_filter: nil)
      new(current_user:, pull_request:, limit_config:, cap_filter:).load_initial_page
    end

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: PullRequest,
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        after_cursor: T.nilable(String),
        page: Integer
      ).returns(PaginatedResult)
    end
    def self.load_with_cursor(current_user:, pull_request:, limit_config:, cap_filter: nil, after_cursor: nil, page: 1)
      new(current_user:, pull_request:, limit_config:, cap_filter:, after_cursor:, page:).load_with_cursor
    end

    sig do
      params(
        current_user: T.nilable(User),
        pull_request: PullRequest,
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
        after_cursor: T.nilable(String),
        page: Integer
      ).void
    end
    def initialize(current_user:, pull_request:, limit_config:, cap_filter: nil, after_cursor: nil, page: 1)
      @current_user = current_user
      @pull_request = pull_request
      @limit_config = limit_config
      @cap_filter = cap_filter
      @after_cursor = after_cursor
      @page = page
    end

    # Load the initial page using apply_page_limit for consistency with existing behavior.
    # The cursor returned is the last (lowest) ID from the initial page.
    sig { returns(PaginatedResult) }
    def load_initial_page
      with_telemetry do
        with_database_error_fallback(fallback: PaginatedResult.empty(page: 1)) do
          threads_relation = @limit_config.apply_page_limit(
            PullRequests::PageData::Files::PageLimitConfig::LimitType::ReviewThreads,
            count_exceeds_paginated_max_block: ->(paginated_max) {
              # Check if there are more threads beyond the paginated max limit
              build_threads_query.offset(paginated_max).exists?
            }
          ) do |limit|
            build_threads_query.limit(limit)
          end

          threads = threads_relation.to_a

          has_next_page = @limit_config.review_threads_limit_exceeded?
          # Use last thread's ID as cursor for keyset pagination
          cursor = threads.last&.id&.to_s

          thread_data = load_thread_data(threads)

          PaginatedResult.new(
            items: thread_data,
            page_info: PageInfo.new(
              has_next_page: has_next_page,
              cursor: cursor,
              page: 1
            )
          )
        end
      end
    end

    # Load subsequent pages using cursor-based pagination with total limit enforcement.
    sig { returns(PaginatedResult) }
    def load_with_cursor
      with_telemetry do
        with_database_error_fallback(fallback: PaginatedResult.empty(page: @page)) do
          page_size = @limit_config.review_threads_limit
          total_limit = @limit_config.review_threads_paginated_limit

          # Calculate how many threads have been loaded in previous pages
          previously_loaded = (@page - 1) * page_size
          remaining_budget = total_limit - previously_loaded

          # If we've already hit the total limit, return empty result
          if remaining_budget <= 0
            return PaginatedResult.empty(page: @page)
          end

          # Don't fetch more than our remaining budget
          effective_limit = [page_size, remaining_budget].min

          # Use keyset pagination with cursor
          threads_with_extra = build_threads_query(cursor: @after_cursor)
            .limit(effective_limit + 1)
            .to_a

          has_more_in_db = threads_with_extra.size > effective_limit
          threads = has_more_in_db ? threads_with_extra.take(effective_limit) : threads_with_extra

          # Calculate total loaded after this page
          total_loaded_after = previously_loaded + threads.size

          # Has next page only if DB has more AND we haven't hit total limit
          has_next_page = !!(has_more_in_db && total_loaded_after < total_limit)

          thread_data = load_thread_data(threads)

          PaginatedResult.new(
            items: thread_data,
            page_info: PageInfo.new(
              has_next_page: has_next_page,
              cursor: threads.last&.id&.to_s,
              page: @page
            )
          )
        end
      end
    end

    private

    # Build the base query for threads with proper visibility and ordering
    sig { params(cursor: T.nilable(String)).returns(ActiveRecord::Relation) }
    def build_threads_query(cursor: nil)
      base = @pull_request.review_threads.visible_to(@current_user)

      # Order by ID for consistent cursor-based pagination
      ordered = base.reorder(id: :desc)

      # Apply cursor for pagination if provided
      if cursor.present?
        ordered.where("id < ?", cursor)
      else
        ordered
      end
    end

    # Load full thread data with comments for multiple threads
    sig do
      params(
        threads: T::Enumerable[PullRequestReviewThread]
      ).returns(T::Array[PullRequestThreadData])
    end
    def load_thread_data(threads)
      threads_array = threads.to_a
      return [] if threads_array.empty?

      thread_result_by_thread_id = load_comments_by_thread_id(threads_array)

      thread_promises = threads_array.map do |thread|
        Promise.all([
          thread.async_viewer_can_reply?(@current_user),
          thread.async_resolver_for(@current_user)
        ]).then do |viewer_can_reply, resolved_by|
          thread_result = thread_result_by_thread_id[thread.id]

          next unless thread_result

          PullRequestThreadData.new(
            id: thread.id,
            is_resolved: thread.resolved?,
            resolved_by: resolved_by,
            viewer_can_reply: viewer_can_reply,
            thread_comments: thread_result.review_comments,
            subject_type: thread.subject_type || "line",
            review_comments_limit_exceeded: thread_result.review_comments_limit_exceeded,
            review_comments_limit: @limit_config.review_comments_per_thread_limit,
          )
        end
      end

      Promise.all(thread_promises).sync
    end

    # Load comments for threads with per-thread limits
    sig do
      params(
        threads: T::Enumerable[PullRequestReviewThread]
      ).returns(T::Hash[Integer, PullRequests::PageData::Files::PageLimitConfig::ReviewCommentsLimitResult])
    end
    def load_comments_by_thread_id(threads)
      @limit_config.apply_review_comments_per_thread_limit do |limit|
        PullRequests::PageData::ThreadComments::Loader.load(
          current_user: @current_user,
          threads: threads,
          cap_filter: @cap_filter,
          max_comments: limit
        )
      end
    end
  end
end
