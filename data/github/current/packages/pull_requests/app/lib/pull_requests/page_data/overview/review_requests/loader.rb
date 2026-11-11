# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Overview::ReviewRequests
  class Loader
    include GitHub::ResilienceMixin
    include PullRequests::PageData::Telemetry

    # Maximum number of review IDs to include in the thread-count query.
    # Beyond this threshold we skip the aggregation to avoid long-running queries.
    # p99 for reviews per PR is 20, so this should cover the vast majority of cases while protecting against outliers.
    MAX_REVIEW_IDS_FOR_THREAD_QUERY = 100

    sig { returns(PullRequest) }
    attr_reader :pull_request

    class ReviewState < T::Enum
      enums do
        Pending = new("pending")
        Commented = new("commented")
        Approved = new("approved")
        ChangesRequested = new("changes_requested")
        Dismissed = new("dismissed")
      end
    end

    class ReviewerType < T::Enum
      enums do
        User = new("User")
        Team = new("Team")
      end
    end

    class DeferredType < T::Enum
      enums do
        Codeowner = new("codeowner")
        Copilot = new("copilot")
      end
    end

    class ReviewerData < T::Struct
      const :id, Integer
      const :display_login, String
      const :name, T.nilable(String)
      const :avatar_url, String
      const :reviewer_type, ReviewerType
      const :organization_login, T.nilable(String)
    end

    class PendingReviewRequestData < T::Struct
      const :reviewer, ReviewerData
      const :is_code_owner, T::Boolean
      const :is_code_owner_from_delegation, T::Boolean
      const :deferred_type, T.nilable(DeferredType)
      const :delegated_from_team, T.nilable(ReviewerData)
      # DEPRECATED: Will be removed in favor of delegated_from_team
      const :delegated_from_team_name, T.nilable(String)
      # ISO 8601 timestamp; nil for deferred (non-persisted) requests.
      const :created_at, T.nilable(String)
    end

    class CompletedReviewData < T::Struct
      const :review_id, Integer
      const :reviewer, ReviewerData
      const :state, ReviewState
      const :head_sha, String
      const :submitted_at, String
      const :has_write_access, T::Boolean
      const :can_re_request, T::Boolean
      const :thread_count, Integer
      const :resolved_thread_count, Integer
      const :on_behalf_of_teams, T::Array[ReviewerData]
      # DEPRECATED: Will be removed in favor of on_behalf_of_teams
      const :on_behalf_of_team_names, T::Array[String]
    end

    class SuggestedReviewerData < T::Struct
      const :reviewer, ReviewerData
      const :description, String
    end

    class ReviewersData < T::Struct
      const :pending_review_requests, T::Array[PendingReviewRequestData]
      const :completed_reviews, T::Array[CompletedReviewData]
      const :suggested_reviewers, T::Array[SuggestedReviewerData]
    end

    sig { params(pull_request: PullRequest, current_user: T.nilable(::User)).returns(ReviewersData) }
    def self.load(pull_request:, current_user: nil)
      new(pull_request:, current_user:).load
    end

    sig { params(pull_request: PullRequest, current_user: T.nilable(::User)).void }
    def initialize(pull_request:, current_user: nil)
      @pull_request = pull_request
      @current_user = current_user
    end

    sig { returns(ReviewersData) }
    def load
      ReviewersData.new(
        pending_review_requests: load_pending_review_requests,
        completed_reviews: load_completed_reviews,
        suggested_reviewers: load_suggested_reviewers,
      )
    end

    private

    sig { returns(T::Array[PendingReviewRequestData]) }
    def load_pending_review_requests
      with_database_error_fallback(fallback: []) do
        requests = @pull_request.pending_review_requests.to_a
        requests += @pull_request.deferred_code_owner_review_requests(requests)
        requests += @pull_request.deferred_copilot_review_requests(requests)
        codeowner_reviewers = @pull_request.codeowners

        if @current_user
          requests = filter_visible_requests(@current_user, requests)
        end

        # Prefill associations for both direct reviewers and delegating teams so that
        # the visibility batch method below can resolve orgs from cache, not per-team queries.
        all_reviewers = requests.map(&:reviewer)
        all_reviewers += requests.filter_map { |r| r.assigned_from_review_request&.reviewer }
        prefill_reviewer_associations(all_reviewers)

        # Batch-prefill visibility of delegating teams to avoid exposing secret team data.
        if @current_user
          GitHub::PrefillAssociations.prefill_batch_method(requests, :prelude_visible_assigned_from_team, @current_user)
        end

        requests.map { |request| build_pending_review_request_data(request, codeowner_reviewers) }
      end
    end

    sig { returns(T::Array[CompletedReviewData]) }
    def load_completed_reviews
      with_database_error_fallback(fallback: []) do
        reviews = @current_user ? @pull_request.visible_sidebar_reviews(@current_user) : []

        prefill_copilot_co_author_check(reviews)

        effective_reviews_map = T.let({}, T::Hash[PullRequestReview, PullRequestReview])
        write_access_by_review = T.let({}, T::Hash[PullRequestReview, T::Boolean])
        copilot_repo_approval_settings_by_repository_id =
          PullRequestReview.copilot_repo_approval_settings_by_repository_id_for(
            reviews,
            repository: @pull_request.repository,
          )
        copilot_qualified_approval_policy_by_repository_id = {}
        Promise.all([
          Promise.all(reviews.map do |review|
            review.async_author_is_qualified_reviewer?(
              copilot_repo_approval_settings_by_repository_id:,
              copilot_qualified_approval_policy_by_repository_id:,
            ).then do |has_access|
              write_access_by_review[review] = has_access
            end
          end),
          Promise.all(reviews.map do |review|
            if review.commented?
              review.async_user.then do |user|
                if (enforced_review = @pull_request.latest_enforced_review_for(user))
                  effective_reviews_map[review] = enforced_review
                  enforced_review.async_author_is_qualified_reviewer?(
                    copilot_repo_approval_settings_by_repository_id:,
                    copilot_qualified_approval_policy_by_repository_id:,
                  ).then do |has_access|
                    write_access_by_review[enforced_review] = has_access
                  end
                else
                  effective_reviews_map[review] = review
                end
              end
            else
              effective_reviews_map[review] = review
            end
          end),
        ]).sync

        effective_reviews = effective_reviews_map.values.uniq

        GitHub::PrefillAssociations.prefill_associations(effective_reviews, [:user, :pull_request_reviews_review_requests, :repository])
        GitHub::PrefillAssociations.prefill_batch_method(effective_reviews, :prelude_on_behalf_of_visible_teams_for, @current_user)

        user_reviewers = effective_reviews.map { |r| T.let(r.user, T.nilable(User)) }.compact
        prefill_reviewer_associations(user_reviewers)

        # Aggregate thread counts per reviewer across all their reviews on this PR.
        # A reviewer may submit comments individually (each creating a separate review)
        # rather than batching them into a single review, so we count threads across
        # all reviews by each user to get accurate totals.
        #
        # We use two single-table queries instead of a JOIN so the thread query
        # can use the efficient pull_request_review_id index rather than scanning
        # all threads on the PR via pull_request_id.
        reviewer_user_ids = effective_reviews.filter_map(&:user_id).uniq
        thread_counts_by_user = T.let({}, T::Hash[Integer, Integer])
        resolved_counts_by_user = T.let({}, T::Hash[Integer, Integer])

        if reviewer_user_ids.any?
          # Step 1: Collect all review IDs for these users on this PR
          review_id_to_user_id = T.let({}, T::Hash[Integer, Integer])
          PullRequestReview
            .where(pull_request_id: @pull_request.id, user_id: reviewer_user_ids)
            .pluck(:id, :user_id)
            .each { |rid, uid| review_id_to_user_id[rid] = uid }

          all_review_ids = review_id_to_user_id.keys

          # Step 2: Count threads per review using the pull_request_review_id index
          if all_review_ids.any? && all_review_ids.size <= MAX_REVIEW_IDS_FOR_THREAD_QUERY
            PullRequestReviewThread
              .where(pull_request_review_id: all_review_ids)
              .group(:pull_request_review_id)
              .pluck(:pull_request_review_id, Arel.sql("COUNT(*)"), Arel.sql("COUNT(resolver_id)"))
              .each do |review_id, total, resolved|
                uid = T.must(review_id_to_user_id[review_id])
                thread_counts_by_user[uid] = (thread_counts_by_user[uid] || 0) + total
                resolved_counts_by_user[uid] = (resolved_counts_by_user[uid] || 0) + resolved
              end
          end
        end

        effective_reviews.map do |review|
          build_completed_review_data(
            review,
            write_access_by_review,
            thread_counts_by_user,
            resolved_counts_by_user,
          )
        end
      end
    end

    sig { returns(T::Array[SuggestedReviewerData]) }
    def load_suggested_reviewers
      with_database_error_fallback(fallback: []) do
        return [] unless @current_user
        return [] if skip_suggested_reviewers?
        return [] unless @pull_request.include_reviewer_suggestions?(user: @current_user)

        suggestions = @pull_request.suggested_reviewers(actor: @current_user)

        user_reviewers = suggestions.map(&:user)
        prefill_reviewer_associations(user_reviewers)

        suggestions.map { |suggestion| build_suggested_reviewer_data(suggestion) }
      end
    end

    sig { params(reviewers: T::Array[T.any(User, Team)]).void }
    def prefill_reviewer_associations(reviewers)
      users = reviewers.grep(User)
      teams = reviewers.grep(Team)

      if users.any?
        GitHub::PrefillAssociations.prefill_associations(
          users,
          [{ user_status: :organization }, { business_user_accounts: :business }],
        )
      end

      if teams.any?
        GitHub::PrefillAssociations.prefill_associations(teams, [:organization])
      end
    end

    # Batch-filter visible requests using Promise.all to allow the team member
    # check loader to batch across all team requests in a single query.
    sig { params(viewer: User, requests: T::Array[ReviewRequest]).returns(T::Array[ReviewRequest]) }
    def filter_visible_requests(viewer, requests)
      # Prefill team organizations before visibility checks to avoid per-team org loads.
      team_reviewers = requests.filter_map { |r| r.reviewer if r.reviewer.is_a?(Team) }
      GitHub::PrefillAssociations.prefill_associations(team_reviewers, [:organization]) if team_reviewers.any?

      visibilities = Promise.all(
        requests.map { |r| r.async_visible_subject_for(viewer) }
      ).sync

      requests.zip(visibilities).filter_map { |request, visible| request if visible }
    end

    # Pre-warm the pull_request's is_copilot_co_author? memoization for all
    # reviewer user_ids with a single WHERE user_id IN (...) query, avoiding
    # per-reviewer EXISTS queries inside async_author_is_qualified_reviewer?.
    sig { params(reviews: T::Array[PullRequestReview]).void }
    def prefill_copilot_co_author_check(reviews)
      user_ids = reviews.filter_map(&:user_id).uniq
      return if user_ids.empty?

      @pull_request.prefill_copilot_co_author_cache(user_ids)
    end

    sig { returns(T::Boolean) }
    def skip_suggested_reviewers?
      # Feature flag for large organizations that are seeing 5000ms+ load times when loading the reviewers menu.
      T.must(@pull_request.repository).feature_flag_enabled?(:skip_suggested_reviewers_by_repo, default: false) ||
        T.must(@pull_request.repository).organization&.feature_flag_enabled?(:skip_suggested_reviewers_by_repo, default: false) ||
        false
    end

    sig { params(reviewer: T.any(User, Team)).returns(ReviewerData) }
    def build_reviewer_data(reviewer)
      if reviewer.is_a?(Team)
        org = reviewer.organization if reviewer.organization_id == T.must(@pull_request.repository).organization_id
        ReviewerData.new(
          id: reviewer.id,
          display_login: reviewer.to_s,
          name: reviewer.name,
          avatar_url: reviewer.primary_avatar_url(40),
          reviewer_type: ReviewerType::Team,
          organization_login: org&.display_login,
        )
      else
        ReviewerData.new(
          id: reviewer.id,
          display_login: reviewer.display_login,
          name: reviewer.display_name,
          avatar_url: reviewer.primary_avatar_url(40),
          reviewer_type: ReviewerType::User,
        )
      end
    end

    sig { params(request: ReviewRequest, codeowner_reviewers: T.untyped).returns(PendingReviewRequestData) }
    def build_pending_review_request_data(request, codeowner_reviewers)
      reviewer = request.reviewer
      delegated = request.assigned_from_review_request.present?

      deferred_type = if request.deferred_code_owner?
        DeferredType::Codeowner
      elsif request.deferred_copilot?
        DeferredType::Copilot
      end

      # Only expose delegating team data if the viewer can see it (secret teams stay hidden).
      delegated_from_team = if delegated && @current_user
        visible_team = request.prelude_visible_assigned_from_team(@current_user)
        build_reviewer_data(visible_team) if visible_team
      end

      is_code_owner_from_delegation = delegated &&
        codeowner_reviewers&.include?(T.must(request.assigned_from_review_request).reviewer) || false

      PendingReviewRequestData.new(
        reviewer: build_reviewer_data(reviewer),
        is_code_owner: codeowner_reviewers&.include?(reviewer) || false,
        is_code_owner_from_delegation: is_code_owner_from_delegation,
        deferred_type: deferred_type,
        delegated_from_team: T.let(delegated_from_team, T.nilable(ReviewerData)),
        delegated_from_team_name: delegated_from_team&.name,
        created_at: request.created_at&.iso8601,
      )
    end

    sig do
      params(
        review: PullRequestReview,
        write_access_by_review: T::Hash[PullRequestReview, T::Boolean],
        thread_counts: T::Hash[Integer, Integer],
        resolved_counts: T::Hash[Integer, Integer],
      ).returns(CompletedReviewData)
    end
    def build_completed_review_data(review, write_access_by_review, thread_counts, resolved_counts)
      reviewer = review.user || User.ghost

      copilot_bot = reviewer.is_a?(Bot) && reviewer.slug == Apps::Privileged::CopilotPullRequestReviewer::SLUG
      has_write_access = write_access_by_review[review] || copilot_bot

      on_behalf_of_teams = review.prelude_on_behalf_of_visible_teams_for(@current_user).sort_by(&:created_at)

      CompletedReviewData.new(
        review_id: review.id,
        reviewer: build_reviewer_data(reviewer),
        state: ReviewState.deserialize(review.current_state.name.to_s),
        head_sha: review.head_sha,
        submitted_at: (review.submitted_at || review.created_at).iso8601,
        has_write_access: has_write_access,
        can_re_request: can_re_request_review?(reviewer),
        thread_count: thread_counts[review.user_id] || 0,
        resolved_thread_count: resolved_counts[review.user_id] || 0,
        on_behalf_of_teams: on_behalf_of_teams.map { |team| build_reviewer_data(team) },
        on_behalf_of_team_names: on_behalf_of_teams.map(&:name),
      )
    end

    # Single source of truth for whether the current user can re-request a review
    # from a given reviewer. Mirrors the three conditions from the ERB sidebar:
    #   1. PR must be open
    #   2. Current user must have re-request permission (PR author or :request_pr_review authz)
    #   3. Reviewer must be eligible (all humans are; bots only if Copilot reviewer + user has access)
    sig { params(reviewer: T.any(User, Team)).returns(T::Boolean) }
    def can_re_request_review?(reviewer)
      return false unless @current_user
      return false unless @pull_request.open?
      return false unless @pull_request.can_re_request_review?(@current_user)

      # Human users are always eligible
      return true if reviewer.is_a?(User) && !reviewer.is_a?(Bot)

      # For bots, only allow the Copilot Pull Request Reviewer bot.
      # Gracefully degrade to false if the Copilot cluster is unavailable,
      # so we never block the review requests panel on Copilot availability.
      with_database_error_fallback(fallback: false) do
        reviewer_app = Apps::Privileged.integration(:copilot_pull_request_reviewer)
        next false unless reviewer_app.present? && reviewer.is_a?(Bot) && reviewer_app.bot.id == reviewer.id

        access = PullRequests::Copilot::CodeReviewAccess.new(actor: @current_user, current_repository: @pull_request.repository)
        access.can_create_review_request?
      end
    end

    sig { params(suggestion: PullRequest::SuggestedReviewer).returns(SuggestedReviewerData) }
    def build_suggested_reviewer_data(suggestion)
      SuggestedReviewerData.new(
        reviewer: build_reviewer_data(suggestion.user),
        description: suggestion.description,
      )
    end
  end
end
