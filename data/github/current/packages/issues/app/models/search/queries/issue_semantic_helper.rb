# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module IssueSemanticHelper
      include GitHub::Memoizer
      extend T::Helpers
      abstract!

      requires_ancestor { IssueQuery }

      # Controls whether a repository (or its owner) is enabled for bulk indexing (e.g. index repair)
      sig { params(repository: T.nilable(Repository)).returns(T::Boolean) }
      def self.ingest_enabled?(repository:)
        return true if repository&.feature_flag_enabled?(:elasticsearch_semantic_indexing_issues, default: false)
        return true if repository&.owner&.feature_flag_enabled?(:elasticsearch_semantic_indexing_issues, default: false)
        false
      end

      # Controls whether a repository (or its owner) is enabled for semantic search
      # Distinct from ingest so that we can block search on a repository that is not yet fully indexed
      # Distinct from the user flag so we can switch between lexical and semantic search
      sig { params(repository: T.nilable(Repository)).returns(T::Boolean) }
      def self.search_enabled?(repository:)
        return true if repository&.feature_flag_enabled?(:elasticsearch_semantic_querying_issues, default: false)
        return true if repository&.owner&.feature_flag_enabled?(:elasticsearch_semantic_querying_issues, default: false)
        false
      end

      # Controls whether the user is enabled for semantic search, across multiple experiences
      sig { params(user: T.nilable(User)).returns(T::Boolean) }
      def self.search_demo_enabled?(user:)
        !!user&.feature_preview_enabled?(:elasticsearch_semantic_indexing_issues_semantic_search)
      end

      def initialize(opts = {}, &block)
        opts[:quote_words] = false

        # In Elasticsearch, top level size has an influence on semantic search as queries, by default, uses its value
        # to fetch the number of nearest neighbors to return from each shard unless it is set otherwise in k through Knn queries.
        #
        # Today, because we use size: 25 to fetch list of issues while use size: 10 for aggregations (open vs. closed counts),
        # we sometimes show incorrect counts for semantic searches.
        #
        # Updating the default size to force all semantic search queries to use 25 as default page size including aggregation queries.
        opts[:per_page] = 25

        super(opts, &block)

        @index = index_for_type_param
      end

      memoize def index_for_type_param
        index_name = index_name_for_type_param
        if index_name == "pull-requests"
          # To make sure PR searches are behaving the same as before
          @quote_words = true
          @query = quote_words(@query)
          self.escaped_query = @query
          Elastomer::Indexes::Issues.searcher(index_name + Elastomer.env.postfix.to_s)
        else
          Elastomer::Indexes::IssuesSemantic.new
        end
      end

      def issues_semantic_index?
        index.name.include?("issues-semantic")
      end

      def use_semantic_query?
        return false if @repo_id.nil?
        return false unless issues_semantic_index?
        repository = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
          T.cast(::Repositories.domain.by_id(@repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
        else
          Repository.find_by(id: @repo_id)
        end
        IssueSemanticHelper.search_enabled?(repository:)
      end

      def build_semantic_function_query(escaped_query)
        {
          bool: {
            should: [
              {
                semantic: {
                  field: "title_semantic",
                  query: escaped_query,
                  boost: 1.5
                }
              },
              {
                semantic: {
                  field: "body_semantic",
                  query: escaped_query,
                  boost: 1.0
                }
              },
              {
                semantic: {
                  field: "comment_body_semantic",
                  query: escaped_query,
                  boost: 0.8
                }
              }
            ],
            minimum_should_match: 1
          }
        }
      end

      def prune_results(results)
        issue_ids = []
        pull_request_ids = []
        error_reported = false

        results.each do |h|
          doc_id = h["_id"].to_i
          index_name = Elastomer.get_index_name_from_result(h)

          case index_name
          when "issues", "issues-semantic"; issue_ids << doc_id
          when "pull-requests"; pull_request_ids << doc_id
          end
        end

        issues = Instrumentation.track_time("search.dist.time", tags: ["index:#{index.name}", "action:prune_results_issues_lookup"]) do
          Issue.includes(:user, :repository).where(id: issue_ids).index_by(&:id)
        end

        pull_requests = ::PullRequest.includes(:user, :issue, :repository).where(id: pull_request_ids).index_by(&:id)

        results.delete_if do |h|
          doc_id = h["_id"].to_i

          index_name = Elastomer.get_index_name_from_result(h)

          case index_name
          when "issues", "issues-semantic"; prune_issue(h, issues[doc_id])
          when "pull-requests"; prune_pull_request(h, pull_requests[doc_id])
          end
        end
      end
    end
  end
end
