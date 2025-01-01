# typed: true
# frozen_string_literal: true

module Search
  module Queries
    # Uses a set of filters passed in to return an aggregated list of
    # private repositories that match the filters. Used by IssueQuery
    # to improve issue and PR search results.
    # See PRs https://github.com/github/github/pull/191720 and
    # https://github.com/github/github/pull/193853 for more details.
    class CandidatePrivateRepoQuery < Query
      def initialize(filters, opts = {}, &block)
        @filter_hash = filters

        @index = opts.fetch(:index, Elastomer::Indexes::Issues.searcher)
        @query_params = opts.fetch(:query_params, {})

        opts[:per_page] ||= 0

        super(opts, &block)
      end

      attr_reader :query_params

      # adds our private repo filter to the passed-in filter hash
      def filter_hash
        @filter_hash.merge(private_repo_filter_hash)
      end

      def build_query
        {
          bool: {
            filter: Search::Filters::BoolFilter.new(filter_hash).build
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

      private

      def private_repo_filter_hash
        private_repo_quals = Search::ParsedQuery.qualifiers
        private_repo_quals[:public].must(false)

        { public: Search::Filters::TermFilter.new(qualifiers: private_repo_quals, field: :public) }
      end
    end
  end
end
