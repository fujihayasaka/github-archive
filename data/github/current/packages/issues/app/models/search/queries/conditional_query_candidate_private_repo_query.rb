# typed: true
# frozen_string_literal: true

module Search
  module Queries
    # Because of the nested structure of queries being supported in `Search::Queries::ConditionalIssueQuery`
    # using the flat list of qualifiers to make the Candidate Repo Search Query (the way it is currently done in `Search::Queries::CandidatePrivateRepoQuery`)
    # wouldn't have the same semantics (because any of the terms used in the Query could be AND-ed/OR-ed etc).

    # Here, Instead of sending a subset of qualifiers in the search string to make the aggregate query,
    # we send the entire nested query. This would, arguably, result in a higher "quality" list of repos
    # in terms of matches because we will be returning repo_ids that are guaranteed to have issues
    # that match the entire query string, and not just a subset of qualifiers.

    class ConditionalQueryCandidatePrivateRepoQuery < Query

      # query: the conditional(nested) query that will be used to perform an aggregated query (ex: label:bug OR assignee:monalisa)
      def initialize(query, opts = {}, &block)
        @candidate_query = query
        @index = opts.fetch(:index, Elastomer::Indexes::Issues.searcher)
        @query_params = opts.fetch(:query_params, {})

        opts[:per_page] ||= 0

        super(opts, &block)
      end

      attr_reader :query_params

      # We are overriding this method to return an empty hash
      # Because all filters will be included in the `query` parameter
      # Which is the entire nested query
      def filter_hash
        {}
      end

      def build_query
        {
          bool: {
            must: [@candidate_query, { term: { public: false } }].compact
          }
        }
      end

      def aggregations?; true; end

      def build_aggregations
        {
          repo_ids: {
            terms: { field: "repo_id", size: Search::Filters::RepositoryFilter::MAX_REPO_FILTER_SIZE }
          }
        }
      end
    end
  end
end
