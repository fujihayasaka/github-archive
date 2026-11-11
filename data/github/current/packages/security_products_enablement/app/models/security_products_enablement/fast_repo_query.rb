# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  # A RepoQuery subclass optimized for batch model hydration.
  #
  # Instead of loading Repository models one-by-one from search results,
  # this class batch-loads all models in a single query and attaches them
  # to the search results, avoiding N+1 queries.
  #
  # Used by:
  # - SecretScanning::BulkEnablementQuery (SRA repo picker)
  # - SecurityProductsEnablement::CodeSecurityRiskAssessmentReposQuery (CSRA scanning repo picker)
  class FastRepoQuery < Search::Queries::RepoQuery
    Results = T.type_alias { T::Array[T::Hash[String, T.untyped]] }

    sig { params(results: Results).returns(Results) }
    def prune_results(results)
      repo_ids = results.map { |result| result["_id"] }
      repos_by_id = ::Repository.where(id: repo_ids).index_by(&:id)

      results.keep_if do |result|
        repo_id = result["_id"].to_i
        repo = repos_by_id[repo_id]

        result["_model"] = repo
      end
    end
  end
end
