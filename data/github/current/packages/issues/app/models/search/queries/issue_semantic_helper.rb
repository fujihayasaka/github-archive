# typed: true
# frozen_string_literal: true

require_relative "embedding_error"

module Search
  module Queries
    module IssueSemanticHelper
      include GitHub::Memoizer
      extend T::Helpers
      abstract!

      requires_ancestor { IssueQuery }

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
      end

      def build_semantic_function_query(escaped_query)
        if use_knn_search?
          query_vector = fetch_embedding_vector(escaped_query)

          {
            bool: {
              should: [
                {
                  knn: {
                    field: "title_dense_vector",
                    query_vector: query_vector,
                    boost: 1.5
                  }
                },
                {
                  knn: {
                    field: "body_dense_vector",
                    query_vector: query_vector,
                    boost: 1.0
                  }
                },
              ],
              minimum_should_match: 1
            }
          }
        else
          build_legacy_semantic_query(escaped_query)
        end
      end

      def build_legacy_semantic_query(escaped_query)
        {
          bool: {
            should: [
              {
                semantic: {
                  field: "title_dense_vector",
                  query: escaped_query,
                  boost: 1.5
                }
              },
              {
                semantic: {
                  field: "body_dense_vector",
                  query: escaped_query,
                  boost: 1.0
                }
              },
            ],
            minimum_should_match: 1
          }
        }
      end

      def fetch_embedding_vector(text)
        return nil if text.blank?

        begin
          response = index.client.post(
            "/_inference/{task_type}/{inference_id}",
            {
              task_type: "text_embedding",
              inference_id: "issues-prs-azure-embeddings",
              body: { input: text },
              rest_api: "inference.inference"
            }
          )
        rescue StandardError => e
          Rails.logger.error("Failed to fetch embedding: #{e.message}")
          raise Search::Queries::EmbeddingError::EmbeddingFetchError.new(e)
        end

        embedding = response.body.dig("text_embedding", 0, "embedding")
        raise Search::Queries::EmbeddingError::InvalidEmbeddingResponseError.new(response.body) if embedding.nil?

        embedding
      end

      def use_knn_search?
        FeatureFlag.vexi.enabled?(:semantic_issues_knn_search, @current_user, default: false)
      end

      def prune_results(results)
        issue_ids = []
        pull_request_ids = []
        error_reported = false

        results.each do |h|
          doc_id = h["_id"].to_i
          index_name = Elastomer.get_index_name_from_result(h)

          case index_name
          when "issues"; issue_ids << doc_id
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
          when "issues"; prune_issue(h, issues[doc_id])
          when "pull-requests"; prune_pull_request(h, pull_requests[doc_id])
          end
        end
      end
    end
  end
end
