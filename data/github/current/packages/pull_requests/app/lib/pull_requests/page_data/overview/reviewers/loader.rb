# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Overview::Reviewers
  class Loader
    include GitHub::ResilienceMixin

    sig { returns(PullRequest) }
    attr_reader :pull_request

    class ReviewerData < T::Struct
      const :id, Integer
      const :display_login, String
      const :name, T.nilable(String)
      const :avatar_url, String
      const :reviewer_type, PullRequests::PageData::Overview::ReviewRequests::Loader::ReviewerType
      const :organization_login, T.nilable(String)
    end

    class ReviewersData < T::Struct
      # The filtered set of users and teams the current viewer may request a review from.
      const :available_reviewers, T::Array[ReviewerData]
    end

    sig do
      params(
        pull_request: PullRequest,
        current_user: T.nilable(::User),
        search_query: String,
      ).returns(ReviewersData)
    end
    def self.load(pull_request:, current_user: nil, search_query: "")
      new(pull_request:, current_user:, search_query:).load
    end

    sig do
      params(
        pull_request: PullRequest,
        current_user: T.nilable(::User),
        search_query: String,
      ).void
    end
    def initialize(pull_request:, current_user: nil, search_query: "")
      @pull_request = pull_request
      @current_user = current_user
      @search_query = search_query
    end

    sig { returns(ReviewersData) }
    def load
      ReviewersData.new(
        available_reviewers: load_available_reviewers,
      )
    end

    private

    # Returns the list of users (and, when permitted, teams) that the current
    # viewer may request a review from.
    # Type-ahead is always on for this endpoint, even when no `search_query`
    sig { returns(T::Array[ReviewerData]) }
    def load_available_reviewers
      with_database_error_fallback(fallback: []) do
        return [] unless @current_user
        return [] unless @pull_request.can_request_review?(@current_user)

        reviewers = @pull_request.sorted_reviewers(
          @current_user,
          requests: @pull_request.pending_review_requests,
          search_query: @search_query,
        ).to_a.uniq

        prefill_reviewer_associations(reviewers)

        reviewers.map { |reviewer| build_reviewer_data(reviewer) }
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
          reviewer_type: PullRequests::PageData::Overview::ReviewRequests::Loader::ReviewerType::Team,
          organization_login: org&.display_login,
        )
      else
        ReviewerData.new(
          id: reviewer.id,
          display_login: reviewer.display_login,
          name: reviewer.display_name,
          avatar_url: reviewer.primary_avatar_url(40),
          reviewer_type: PullRequests::PageData::Overview::ReviewRequests::Loader::ReviewerType::User,
        )
      end
    end
  end
end
