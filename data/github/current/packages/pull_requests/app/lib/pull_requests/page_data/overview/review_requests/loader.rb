# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Overview::ReviewRequests
  class Loader
    include GitHub::ResilienceMixin
    include PullRequests::PageData::Telemetry

    sig { returns(PullRequest) }
    attr_reader :pull_request

    class ReviewerData < T::Struct
      const :id, Integer
      const :display_login, String
      const :name, T.nilable(String)
      const :avatar_url, String
      const :reviewer_type, String
      const :organization_login, T.nilable(String)
    end

    class PendingReviewRequestData < T::Struct
      const :reviewer, ReviewerData
      const :is_code_owner, T::Boolean
      const :is_code_owner_from_delegation, T::Boolean
      const :deferred_type, T.nilable(String)
      const :delegated_from_team_name, T.nilable(String)
    end

    class CompletedReviewData < T::Struct
      const :reviewer, ReviewerData
      const :state, String
      const :head_sha, String
      const :has_write_access, T::Boolean
      const :can_re_request, T::Boolean
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
          requests = @pull_request.visible_sidebar_requests(@current_user, requests)
        end

        prefill_reviewer_associations(requests.map(&:reviewer))

        requests.map { |request| build_pending_review_request_data(request, codeowner_reviewers) }
      end
    end

    sig { returns(T::Array[CompletedReviewData]) }
    def load_completed_reviews
      with_database_error_fallback(fallback: []) do
        reviews = @current_user ? @pull_request.visible_sidebar_reviews(@current_user) : []

        write_access_by_review = T.let({}, T::Hash[PullRequestReview, T::Boolean])
        Promise.all([
          Promise.all(reviews.map do |review|
            review.async_author_is_qualified_reviewer?.then do |has_access|
              write_access_by_review[review] = has_access
            end
          end),
          Promise.all(reviews.map do |review|
            if review.commented?
              review.async_user.then do |user|
                if (enforced_review = @pull_request.latest_enforced_review_for(user))
                  enforced_review.async_author_is_qualified_reviewer?.then do |has_access|
                    write_access_by_review[enforced_review] = has_access
                  end
                end
              end
            end
          end),
        ]).sync

        GitHub::PrefillAssociations.prefill_associations(reviews, [:user])
        user_reviewers = reviews.map { |r| T.let(r.user, T.nilable(User)) }.compact
        prefill_reviewer_associations(user_reviewers)

        reviews.map { |review| build_completed_review_data(review, write_access_by_review) }
      end
    end

    sig { returns(T::Array[SuggestedReviewerData]) }
    def load_suggested_reviewers
      with_database_error_fallback(fallback: []) do
        return [] unless @current_user
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

    sig { params(reviewer: T.any(User, Team)).returns(ReviewerData) }
    def build_reviewer_data(reviewer)
      if reviewer.is_a?(Team)
        org = reviewer.organization if reviewer.organization_id == T.must(@pull_request.repository).organization_id
        ReviewerData.new(
          id: reviewer.id,
          display_login: reviewer.to_s,
          name: reviewer.name,
          avatar_url: reviewer.primary_avatar_url(40),
          reviewer_type: "Team",
          organization_login: org&.display_login,
        )
      else
        ReviewerData.new(
          id: reviewer.id,
          display_login: reviewer.display_login,
          name: reviewer.profile_name,
          avatar_url: reviewer.primary_avatar_url(40),
          reviewer_type: "User",
        )
      end
    end

    sig { params(request: ReviewRequest, codeowner_reviewers: T.untyped).returns(PendingReviewRequestData) }
    def build_pending_review_request_data(request, codeowner_reviewers)
      reviewer = request.reviewer
      delegated = request.assigned_from_review_request.present?

      deferred_type = if request.deferred_code_owner?
        "codeowner"
      elsif request.deferred_copilot?
        "copilot"
      end

      delegated_from_team_name = if delegated
        T.must(request.assigned_from_review_request).reviewer.name
      end

      is_code_owner_from_delegation = delegated &&
        codeowner_reviewers&.include?(T.must(request.assigned_from_review_request).reviewer) || false

      PendingReviewRequestData.new(
        reviewer: build_reviewer_data(reviewer),
        is_code_owner: codeowner_reviewers&.include?(reviewer) || false,
        is_code_owner_from_delegation: is_code_owner_from_delegation,
        deferred_type: deferred_type,
        delegated_from_team_name: T.let(delegated_from_team_name, T.nilable(String)),
      )
    end

    sig { params(review: PullRequestReview, write_access_by_review: T::Hash[PullRequestReview, T::Boolean]).returns(CompletedReviewData) }
    def build_completed_review_data(review, write_access_by_review)
      reviewer = review.user || User.ghost

      effective_review = if review.commented?
        @pull_request.latest_enforced_review_for(reviewer) || review
      else
        review
      end

      copilot_bot = reviewer.is_a?(Bot) && reviewer.slug == Apps::Privileged::CopilotPullRequestReviewer::SLUG
      has_write_access = write_access_by_review[effective_review] || copilot_bot

      CompletedReviewData.new(
        reviewer: build_reviewer_data(reviewer),
        state: effective_review.current_state.name.to_s,
        head_sha: review.head_sha,
        has_write_access: has_write_access,
        can_re_request: can_re_request_review?(reviewer),
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
