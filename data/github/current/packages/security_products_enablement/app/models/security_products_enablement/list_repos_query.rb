# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class ListReposQuery
    RESULTS_LIMIT = 10_000

    sig { params(org: Organization, user: User, filter_hash: T::Hash[String, T.untyped], user_session: T.nilable(UserSession)).void }
    def initialize(org:, user:, filter_hash:, user_session: nil)
      @org = org
      @user = user
      @filter_hash = filter_hash
      @user_session = user_session
    end

    sig { returns([T::Array[Integer], T::Boolean]) }
    def repository_ids
      GitHub.dogstats.distribution_time("security_configurations.list_repos_query") do
        filters = [
          Filters::AdvancedFilters.new(@user, @org, @filter_hash, @user_session),
          Filters::SecurityConfiguration.new(@org, @user, @filter_hash),
          Filters::Team.new(@user, @org, @filter_hash)
        ].select(&:can_apply?)

        filter_results = filters.map(&:apply).map(&:to_set)

        repo_ids = filter_results.reduce(:&)
        return [[], false] if repo_ids.nil? || repo_ids.empty?

        # The IDs are sorted to provide some consistency when the results are truncated.
        repo_ids = ::Repository.where(id: repo_ids).order(id: :desc).pluck(:id)

        search_results_limit_exceeded = repo_ids.length > RESULTS_LIMIT
        GitHub.dogstats.increment("security_configurations.search_results_limit_exceeded", tags: ["value:#{search_results_limit_exceeded}"])

        [repo_ids, search_results_limit_exceeded]
      end
    end
  end
end
