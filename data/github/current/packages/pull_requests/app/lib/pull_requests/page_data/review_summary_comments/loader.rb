# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ReviewSummaryComments
  class Loader
    include GitHub::ResilienceMixin
    include PullRequests::PageData::Telemetry

    class ReviewState < T::Enum
      enums do
        Commented = new("COMMENTED")
        Approved = new("APPROVED")
        ChangesRequested = new("CHANGES_REQUESTED")
        Dismissed = new("DISMISSED")
      end
    end

    class ReviewSummary < T::Struct
      const :id, String
      const :state, ReviewState
      const :author_association, String
      const :author_avatar_url, T.nilable(String)
      const :author_login, String
      const :body_html, T.nilable(String)
      const :review, ::PullRequestReview
      const :on_behalf_of_team_name, T.nilable(String)
      const :reaction_groups, T::Array[PullRequests::PageData::Helpers::Reactable::Loader::ReactionGroup]
      const :url, String
      const :viewer_can_react, T::Boolean
    end

    PageInfo = PullRequests::PageData::Pagination::PageInfo

    class PaginatedResult < T::Struct
      const :items, T::Array[ReviewSummary]
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
    # The cursor returned is the last (highest) ID from the page, establishing the snapshot point
    # for all subsequent pagination requests that fetch reviews with id > this cursor.
    sig { returns(PaginatedResult) }
    def load_initial_page
      with_telemetry do
        with_database_error_fallback(fallback: PaginatedResult.empty(page: 1)) do
          base_query = @pull_request.reviews
            .submitted
            .with_review_summary_comment
            .filter_spam_for(@current_user, skip_user_filter_if_not_spammy: true)
            .reorder(id: :asc)

          reviews_relation = @limit_config.apply_page_limit(PullRequests::PageData::Files::PageLimitConfig::LimitType::ReviewSummaryComments) do |limit|
            base_query.limit(limit)
          end

          reviews = reviews_relation.to_a

          has_next_page = @limit_config.review_summary_comments_limit_exceeded?
          # Use last review's ID as cursor for keyset pagination - the next page
          # will fetch reviews with id > this cursor
          cursor = reviews.last&.id&.to_s

          PaginatedResult.new(
            items: build_review_summary_comments(reviews),
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
    # duplicate or missing entries if new reviews are created during pagination.
    sig { returns(PaginatedResult) }
    def load_with_cursor
      with_telemetry do
        with_database_error_fallback(fallback: PaginatedResult.empty(page: @page)) do
          page_size = @limit_config.review_summary_comments_limit
          total_limit = @limit_config.review_summary_comments_paginated_limit

          # Calculate how many reviews have been loaded in previous pages
          previously_loaded = (@page - 1) * page_size
          remaining_budget = total_limit - previously_loaded

          # If we've already hit the total limit, return empty result
          return PaginatedResult.empty(page: @page) if remaining_budget <= 0

          # Don't fetch more than our remaining budget
          effective_limit = [page_size, remaining_budget].min

          base_query = @pull_request.reviews
            .submitted
            .with_review_summary_comment
            .filter_spam_for(@current_user, skip_user_filter_if_not_spammy: true)
            .reorder(id: :asc)
            .where("id > ?", @after_cursor)

          # Fetch limit + 1 to determine if there are more pages
          reviews_with_extra = base_query.limit(effective_limit + 1).to_a
          has_more_in_db = reviews_with_extra.size > effective_limit
          reviews = has_more_in_db ? reviews_with_extra.take(effective_limit) : reviews_with_extra

          # Calculate total loaded after this page
          total_loaded_after = previously_loaded + reviews.size

          # Has next page only if DB has more AND we haven't hit total limit
          has_next_page = !!(has_more_in_db && total_loaded_after < total_limit)

          PaginatedResult.new(
            items: build_review_summary_comments(reviews),
            page_info: PageInfo.new(
              has_next_page: has_next_page,
              cursor: reviews.last&.id&.to_s,
              page: @page
            )
          )
        end
      end
    end

    private

    sig { params(reviews: T::Array[::PullRequestReview]).returns(T::Array[ReviewSummary]) }
    def build_review_summary_comments(reviews)
      return [] if reviews.empty?

      # Preload associations
      associations = [
        :user,
        :pull_request_reviews_review_requests,
        { pull_request: :repository },
        { reactions: :user },
      ]
      ActiveRecord::Associations::Preloader.new(records: reviews, associations: associations).call

      body_html_context = {
        viewer: @current_user,
        cap_filter: @cap_filter,
        unfurl_references: true,
      }

      # Batch preload body_html
      GitHub::PrefillAssociations.prefill_batch_method(reviews, :prelude_body_html, context: body_html_context)

      # Batch preload on_behalf_of teams
      GitHub::PrefillAssociations.prefill_batch_method(reviews, :prelude_on_behalf_of_visible_teams_for, @current_user)

      # Batch viewer permissions
      viewer_can_react_by_review = batch_viewer_can_react(reviews)

      reviews_data = Promise.all(
        reviews.map do |review|
          review_data = {
            author_association: with_async_database_error_fallback(review.author_association.async_to_sym, fallback: :none),
            body_html: review.async_body_html(context: body_html_context),
            reaction_groups: with_async_database_error_fallback(
              PullRequests::PageData::Helpers::Reactable::Loader.async_reaction_groups(review, @current_user),
              fallback: []
            ),
          }

          Promise.all(review_data.values).then do
            on_behalf_of_teams = review.prelude_on_behalf_of_visible_teams_for(@current_user).sort_by(&:created_at)

            state_string = review.current_state.name.to_s.upcase
            state_enum = ReviewState.try_deserialize(state_string) || ReviewState::Commented

            ReviewSummary.new(
              id: review.id.to_s,
              review: review,
              state: state_enum,
              author_association: review_data[:author_association].sync.to_s.upcase,
              author_avatar_url: review.user&.primary_avatar_url,
              author_login: review.user&.display_login || "ghost",
              body_html: review_data[:body_html].sync,
              on_behalf_of_team_name: on_behalf_of_teams.first&.name,
              url: review.permalink,
              viewer_can_react: viewer_can_react_by_review[review] || false,
              reaction_groups: review_data[:reaction_groups].sync,
            )
          end
        end
      ).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      reviews_data
    end

    sig { params(reviews: T::Array[::PullRequestReview]).returns(T::Hash[::PullRequestReview, T::Boolean]) }
    def batch_viewer_can_react(reviews)
      result = {}
      return result unless @current_user && reviews.any?

      promises = reviews.map { |review| review.async_viewer_can_react?(@current_user) }
      results = Promise.all(promises).sync # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      reviews.zip(results).each { |review, can_react| result[review] = can_react }
      result
    end
  end
end
