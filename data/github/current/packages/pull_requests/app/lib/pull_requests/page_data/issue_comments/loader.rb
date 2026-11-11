# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::IssueComments
  class Loader
    include GitHub::ResilienceMixin
    include PullRequests::PageData::Telemetry

    class IssueComment < T::Struct
      const :id, String
      const :author_association, String
      const :author_avatar_url, T.nilable(String)
      const :author_login, String
      const :body_html, String
      const :comment, ::IssueComment
      const :reaction_groups, T::Array[PullRequests::PageData::Helpers::Reactable::Loader::ReactionGroup]
      const :url, String
      const :viewer_can_react, T::Boolean
    end

    PageInfo = PullRequests::PageData::Pagination::PageInfo

    class PaginatedResult < T::Struct
      const :items, T::Array[IssueComment]
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
        comment_id: T.any(String, Integer),
        current_user: T.nilable(User),
        pull_request: PullRequest,
        limit_config: PullRequests::PageData::Files::PageLimitConfig,
        cap_filter: T.nilable(ConditionalAccess::Web::Filter),
      ).returns(T.nilable(IssueComment))
    end
    def self.load_single(comment_id:, current_user:, pull_request:, limit_config:, cap_filter: nil)
      new(current_user:, pull_request:, limit_config:, cap_filter:).load_single(comment_id)
    end

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

    # Load a single issue comment by ID, scoped to the pull request's issue.
    # Returns nil if the comment is not found or does not belong to the PR's issue.
    sig { params(comment_id: T.any(String, Integer)).returns(T.nilable(IssueComment)) }
    def load_single(comment_id)
      with_telemetry do
        with_database_error_fallback(fallback: nil) do
          issue = @pull_request.issue
          return nil unless issue

          comment = issue.comments
            .filter_spam_for(@current_user, skip_user_filter_if_not_spammy: true)
            .find_by(id: comment_id)

          return nil unless comment

          build_issue_comments([comment]).first
        end
      end
    end

    # Load the initial page using apply_page_limit for consistency with existing behavior.
    # The cursor returned is the last (highest) ID from the page, establishing the snapshot point
    # for all subsequent pagination requests that fetch comments with id > this cursor
    sig { returns(PaginatedResult) }
    def load_initial_page
      with_telemetry do
        with_database_error_fallback(fallback: PaginatedResult.empty(page: 1)) do
          issue = @pull_request.issue
          return PaginatedResult.empty(page: 1) unless issue

          base_query = issue.comments
            .filter_spam_for(@current_user, skip_user_filter_if_not_spammy: true)
            .reorder(id: :asc)

          comments_relation = @limit_config.apply_page_limit(PullRequests::PageData::Files::PageLimitConfig::LimitType::IssueComments) do |limit|
            base_query.limit(limit)
          end

          comments = comments_relation.to_a

          has_next_page = @limit_config.issue_comments_limit_exceeded?
          # Use last comment's ID as cursor for keyset pagination - the next page
          # will fetch comments with id > this cursor
          cursor = comments.last&.id&.to_s

          PaginatedResult.new(
            items: build_issue_comments(comments),
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
    # duplicate or missing entries if new comments are created during pagination.
    sig { returns(PaginatedResult) }
    def load_with_cursor
      with_telemetry do
        with_database_error_fallback(fallback: PaginatedResult.empty(page: @page)) do
          issue = @pull_request.issue
          return PaginatedResult.empty(page: @page) unless issue

          page_size = @limit_config.issue_comments_limit
          total_limit = @limit_config.issue_comments_paginated_limit

          # Calculate how many comments have been loaded in previous pages
          previously_loaded = (@page - 1) * page_size
          remaining_budget = total_limit - previously_loaded

          # If we've already hit the total limit, return empty result
          return PaginatedResult.empty(page: @page) if remaining_budget <= 0

          # Don't fetch more than our remaining budget
          effective_limit = [page_size, remaining_budget].min

          base_query = issue.comments
            .filter_spam_for(@current_user, skip_user_filter_if_not_spammy: true)
            .reorder(id: :asc)
            .where("id > ?", @after_cursor)

          # Fetch limit + 1 to determine if there are more pages
          comments_with_extra = base_query.limit(effective_limit + 1).to_a
          has_more_in_db = comments_with_extra.size > effective_limit
          comments = has_more_in_db ? comments_with_extra.take(effective_limit) : comments_with_extra

          # Calculate total loaded after this page
          total_loaded_after = previously_loaded + comments.size

          # Has next page only if DB has more AND we haven't hit total limit
          has_next_page = has_more_in_db && total_loaded_after < total_limit

          PaginatedResult.new(
            items: build_issue_comments(comments),
            page_info: PageInfo.new(
              has_next_page: has_next_page,
              cursor: comments.last&.id&.to_s,
              page: @page
            )
          )
        end
      end
    end

    private

    sig { params(comments: T::Array[::IssueComment]).returns(T::Array[IssueComment]) }
    def build_issue_comments(comments)
      return [] if comments.empty?

      # Preload associations
      associations = [
        :user,
        { issue: :pull_request },
        { issue: { pull_request: :repository } },
        { reactions: :user },
      ]
      ActiveRecord::Associations::Preloader.new(records: comments, associations: associations).call

      body_html_context = {
        viewer: @current_user,
        cap_filter: @cap_filter,
        unfurl_references: true,
      }

      # Batch preload body_html
      GitHub::PrefillAssociations.prefill_batch_method(comments, :prelude_body_html, context: body_html_context)

      # Batch viewer permissions
      viewer_can_react_by_comment = batch_viewer_can_react(comments)

      comments_data = Promise.all(
        comments.map do |comment|
          # Create a hash to make the data more accessible after the promises have resolved
          comment_data = {
            author_association: with_async_database_error_fallback(comment.author_association.async_to_sym, fallback: :none),
            body_html: comment.async_body_html(context: body_html_context),
            reaction_groups: with_async_database_error_fallback(
              PullRequests::PageData::Helpers::Reactable::Loader.async_reaction_groups(comment, @current_user),
              fallback: []
            ),
          }

          Promise.all(comment_data.values).then do
            IssueComment.new(
              id: comment.id.to_s,
              comment: comment,
              author_association: comment_data[:author_association].sync.to_s.upcase,
              author_avatar_url: comment.user&.primary_avatar_url,
              author_login: comment.user&.display_login || "ghost",
              body_html: comment_data[:body_html].sync,
              url: comment.url,
              viewer_can_react: viewer_can_react_by_comment[comment] || false,
              reaction_groups: comment_data[:reaction_groups].sync,
            )
          end
        end
      ).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      comments_data
    end

    sig { params(comments: T::Array[::IssueComment]).returns(T::Hash[::IssueComment, T::Boolean]) }
    def batch_viewer_can_react(comments)
      result = {}
      return result unless @current_user && comments.any?

      promises = comments.map { |comment| comment.async_viewer_can_react?(@current_user) }
      results = Promise.all(promises).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      comments.zip(results).each { |comment, can_react| result[comment] = can_react }
      result
    end
  end
end
