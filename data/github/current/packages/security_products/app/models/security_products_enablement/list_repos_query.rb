# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class ListReposQuery
    extend T::Sig

    RESULTS_LIMIT = 10_000

    sig { params(org: Organization, user: User, filter_hash: T::Hash[String, T.untyped]).void }
    def initialize(org:, user:, filter_hash:)
      @org = org
      @user = user
      @filter_hash = filter_hash
    end

    sig { returns([T::Array[Integer], T::Boolean]) }
    def repository_ids
      repo_ids = Set.new

      repo_ids.merge(Filters::SecurityConfiguration.new(@org, @user, @filter_hash).apply)
      repo_ids.merge(Filters::Team.new(@user, @org, @filter_hash).apply)

      # TODO (allow-archived-repos): Ensure that the repositories are not archived.
      # The IDs are sorted to provide some consistency when the results are truncated.
      repo_ids = Repository.not_archived_scope.where(id: repo_ids).order(id: :desc).pluck(:id)

      # We will pluck the IDs from these results and pass them to an Elasticsearch query.
      # The 10K limit is applied to avoid passing too many IDs in the Elasticsearch query.
      search_results_limit_exceeded = repo_ids.length > RESULTS_LIMIT
      results = search_results_limit_exceeded ? repo_ids.take(RESULTS_LIMIT) : repo_ids
      GitHub.dogstats.increment("security_configurations.search_results_limit_exceeded", tags: ["value:#{search_results_limit_exceeded}"])

      [results, search_results_limit_exceeded]
    end
  end
end
