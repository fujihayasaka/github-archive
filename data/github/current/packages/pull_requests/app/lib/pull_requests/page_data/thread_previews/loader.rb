# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ThreadPreviews
  class Loader
    include GitHub::ResilienceMixin
    include PullRequests::PageData::Telemetry

    # Taken from PullRequests::ReviewThreadDiffLinesComponent::MAX_CONTEXT_LINES
    MAX_CONTEXT_LINES = 3

    class DiffSide < T::Enum
      enums do
        RIGHT = new("RIGHT")
        LEFT = new("LEFT")
      end
    end

    class ThreadSubject < T::Struct
      const :diff_lines, T.nilable(T::Array[T::Hash[Symbol, T.untyped]])
      const :end_line, T.nilable(Numeric)
      const :end_diff_side, T.nilable(DiffSide)
      const :original_end_line, T.nilable(Numeric)
      const :original_start_line, T.nilable(Numeric)
      const :pull_request_commit, T.nilable(String)
      const :start_diff_side, T.nilable(DiffSide)
      const :start_line, T.nilable(Numeric)
    end

    class ThreadPreview < T::Struct
      const :first_comment, T.nilable(T::Array[PullRequests::PageData::ThreadComments::Loader::Comment])
      const :line, T.nilable(Numeric)
      const :id, String
      const :is_outdated, T::Boolean
      const :is_resolved, T::Boolean
      const :path, String
      const :subject, ThreadSubject
      const :subject_type, String
      const :thread_comments, T::Array[PullRequestReviewComment]
      const :original_diff_path_uri, T.nilable(String)
    end

    class ThreadCounts < T::Struct
      const :path, String
      const :thread_count, Integer
    end

    PageInfo = PullRequests::PageData::Pagination::PageInfo

    class PaginatedResult < T::Struct
      const :items, T::Array[ThreadPreview]
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

    sig do params(
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
    # The cursor returned is the first (highest) ID, establishing the snapshot point
    # for all subsequent pagination requests.
    sig { returns(PaginatedResult) }
    def load_initial_page
      with_telemetry do
        with_database_error_fallback(fallback: PaginatedResult.empty(page: 1)) do
          base_query = @pull_request.review_threads
            .visible_to(current_user)
            .reorder(id: :desc)

          threads_relation = @limit_config.apply_page_limit(PullRequests::PageData::Files::PageLimitConfig::LimitType::ReviewThreads) do |limit|
            base_query.limit(limit)
          end

          threads = threads_relation.to_a

          has_next_page = @limit_config.review_threads_limit_exceeded?
          # Use last thread's ID as cursor for keyset pagination - the next page
          # will fetch threads with id < this cursor
          cursor = threads.last&.id&.to_s

          PaginatedResult.new(
            items: build_thread_previews(threads),
            page_info: PageInfo.new(
              has_next_page: has_next_page,
              cursor:,
              page: 1
            )
          )
        end
      end
    end

    # Load subsequent pages using cursor-based pagination with total limit enforcement.
    # The cursor is fixed across all pages to provide a stable snapshot - this prevents
    # duplicate or missing entries if new threads are created during pagination.
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

          # Use keyset pagination - the cursor is the last ID from the previous page,
          # so we fetch threads with id < cursor to get the next batch
          base_query = @pull_request.review_threads
            .visible_to(current_user)
            .reorder(id: :desc)
            .where("id < ?", @after_cursor)

          # Fetch limit + 1 to determine if there are more pages
          threads_with_extra = base_query.limit(effective_limit + 1).to_a
          has_more_in_db = threads_with_extra.size > effective_limit
          threads = has_more_in_db ? threads_with_extra.take(effective_limit) : threads_with_extra

          # Calculate total loaded after this page
          total_loaded_after = previously_loaded + threads.size

          # Has next page only if DB has more AND we haven't hit total limit
          has_next_page = has_more_in_db && total_loaded_after < total_limit

          PaginatedResult.new(
            items: build_thread_previews(threads),
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

    sig { params(threads: T::Array[PullRequestReviewThread]).returns(T::Array[ThreadPreview]) }
    def build_thread_previews(threads)
      repository = T.must(@pull_request.repository)

      if FeatureFlag.vexi.enabled?(:prx_comment_outside_the_diff, repository, repository.owner, default: false)
        comments_by_thread_id = PullRequests::PageData::ThreadComments::Loader.load(
          threads: threads,
          current_user: current_user,
          max_comments: 1,
          cap_filter: cap_filter,
          comment_data_type: PullRequests::PageData::ThreadComments::Loader::CommentDataType::Preview
        )

        positioned_threads = PullRequests::PageData::ThreadPreviewPositioning::Loader.load(
          threads: threads.to_a,
          pull_request: @pull_request,
          max_context_lines: MAX_CONTEXT_LINES
        )

        # Build a map for quick lookup
        positioned_threads_by_id = positioned_threads.index_by(&:thread_id)

        batched_data = threads.each_with_object({}) do |thread, hash|
          # Attempt to reduce diff round trips by reusing our original positioning.
          if original_positioning = thread.original_positioning
            case original_positioning
            when PullRequests::CommentPosition::Positions::Line
              original_start_line = original_positioning.line
              original_end_line = original_positioning.line
            when PullRequests::CommentPosition::Positions::Multiline
              original_start_line = original_positioning.start_line
              original_end_line = original_positioning.end_line
            when PullRequests::CommentPosition::Positions::File
              original_start_line = nil
              original_end_line = nil
            else
              original_start_line = nil
              original_end_line = nil
            end
          end

          hash[thread] = {
            original_end_line: original_end_line ? Promise.resolve(original_end_line) : thread.async_original_line,
            original_start_line: original_start_line ? Promise.resolve(original_start_line) : thread.async_original_start_line,
            review_comments: thread.async_review_comments_for(@current_user),
          }
        end

        Promise.all([pull_request.async_path_uri] + batched_data.values.flat_map(&:values)).sync

        pull_request_path_uri = pull_request.async_path_uri.sync

        threads.map do |thread|
          positioned_thread = positioned_threads_by_id[thread.id]
          thread_comments = (batched_data.dig(thread, :review_comments)&.sync || []).sort_by(&:id)

          is_outdated = positioned_thread.is_outdated

          if thread.outdated
            path_uri = pull_request_path_uri.dup
            path_uri.path += "/files/#{thread.original_commit_id}"

            if id = thread_comments.first&.id
              path_uri.fragment = "#{CommentsHelper::COMMIT_COMMENT_DOM_ID_PREFIX}#{id}"
            end

            original_diff_path_uri = path_uri.to_s
          end

          ThreadPreview.new(
            id: thread.id.to_s,
            first_comment: comments_by_thread_id[thread.id],
            line: positioned_thread&.end_line,
            is_outdated:,
            is_resolved: thread.resolved?,
            path: thread.path,
            subject_type: thread.subject_type,
            subject: ThreadSubject.new(
              diff_lines: positioned_thread&.diff_lines,
              end_line: positioned_thread&.end_line,
              end_diff_side: positioned_thread&.end_diff_side == "LEFT" ? DiffSide::LEFT : DiffSide::RIGHT,
              original_end_line: batched_data.dig(thread, :original_end_line)&.sync,
              original_start_line: batched_data.dig(thread, :original_start_line)&.sync,
              pull_request_commit: positioned_thread&.commit_oid,
              start_diff_side: positioned_thread&.start_diff_side == "LEFT" ? DiffSide::LEFT : DiffSide::RIGHT,
              start_line: positioned_thread&.start_line || positioned_thread&.end_line, # This always has a value, even if there isn't a range.
            ),
            thread_comments:,
            original_diff_path_uri:
          )
        end
      else
        comments_by_thread_id = PullRequests::PageData::ThreadComments::Loader.load(
          threads: threads,
          current_user: current_user,
          max_comments: 1,
          cap_filter: cap_filter,
          comment_data_type: PullRequests::PageData::ThreadComments::Loader::CommentDataType::Preview
        )

        promises = threads.map do |thread|
          thread_data = {
            diff_lines: thread.async_diff_lines(max_context_lines: MAX_CONTEXT_LINES),
            end_side: thread.async_diff_side,
            end_line: thread.async_end_line,
            line: thread.async_line,
            original_diff_path_uri: thread.outdated? ? thread.async_original_diff_path_uri : Promise.resolve(nil),
            original_end_line: thread.async_original_line,
            original_start_line: thread.async_original_start_line,
            review_comments: thread.async_review_comments_for(@current_user),
            start_line: thread.async_start_line,
            start_side: thread.async_start_side,
          }

          Promise.all(thread_data.values).then do
            ThreadPreview.new(
              first_comment: comments_by_thread_id[thread.id],
              line: thread_data[:line].sync,
              id: String(thread.id),
              is_outdated: thread.outdated?,
              is_resolved: thread.resolved?,
              path: thread.path,
              subject_type: thread.subject_type,
              subject: ThreadSubject.new(
                diff_lines: thread_data[:diff_lines].sync,
                end_line: thread_data[:end_line].sync&.position,
                end_diff_side: thread_data[:end_side].sync == :left ? DiffSide::LEFT : DiffSide::RIGHT,
                original_end_line: thread_data[:original_end_line].sync,
                original_start_line: thread_data[:original_start_line].sync,
                pull_request_commit: thread.commit_id,
                start_diff_side: thread_data[:start_side].sync == :left ? DiffSide::LEFT : DiffSide::RIGHT,
                start_line: thread_data[:start_line].sync&.position
              ),
              thread_comments: thread_data[:review_comments].sync,
              original_diff_path_uri: thread_data[:original_diff_path_uri].sync&.to_s
            )
          end
        end

        Promise.all(promises).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end
  end
end
