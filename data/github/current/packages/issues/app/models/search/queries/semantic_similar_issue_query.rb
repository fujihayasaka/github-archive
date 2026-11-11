# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class SemanticSimilarIssueQuery < IssueQuery
      include T::Sig
      include IssueSemanticHelper

      SEARCH_CONTEXT_MAX_LENGTH = 256
      DEFAULT_SEMANTIC_SIMILAR_ISSUE_THRESHOLD = 0.5
      RESCUABLE_ERROR_TYPES = [
        ElastomerClient::Client::ServerError,
        ElastomerClient::Client::RequestError,
        ElastomerClient::Client::TimeoutError,
        ElastomerClient::Client::Error,
        StandardError
      ]

      TITLE_SEMANTIC_WEIGHT = 2
      BODY_SEMANTIC_WEIGHT  = 1.75
      LEXICAL_WEIGHT       = 1

      # Valid values for the target_type parameter that controls which
      # document types are searched (issues, pull requests, or both).
      VALID_TARGET_TYPES = T.let(%w[issue pull-request issue,pull-request pull-request,issue].freeze, T::Array[String])

      # KNN parameters for similar issue search
      SIMILAR_KNN_K = 50
      SIMILAR_KNN_CANDIDATES = 1000

      sig { returns(::Issues::IIssue) }
      attr_reader :issue

      sig { returns(Float) }
      attr_reader :threshold

      # Construct a SemanticSimilarIssueQuery.
      # The query will search for issues and/or pull requests that are
      # semantically similar to the provided issue using KNN vector search.
      #
      # opts - The options Hash.
      #   :issue       - The candidate issue
      #   :threshold   - The minimum similarity threshold for KNN search (default: 0.5)
      #   :target_type - The type of results to return: "issue" (default), "pull-request", or "issue,pull-request"
      sig do
        params(
          opts: T::Hash[Symbol, T.untyped],
          block: T.nilable(T.proc.bind(SemanticSimilarIssueQuery).void)
        ).void
      end
      def initialize(opts = {}, &block)
        @current_user = T.let(opts.fetch(:current_user, nil), T.nilable(::User))
        @issue = T.let(opts.fetch(:issue), ::Issues::IIssue)
        # Validate required parameters
        raise ArgumentError, "Issue cannot be nil" if @issue.nil?

        @threshold = T.let(opts.fetch(:threshold, DEFAULT_SEMANTIC_SIMILAR_ISSUE_THRESHOLD), Float)
        target_type_value = opts[:target_type] || "issue"
        @target_type = T.let(target_type_value, String)

        unless VALID_TARGET_TYPES.include?(@target_type)
          raise ArgumentError,
                "Invalid target_type: #{@target_type}. Valid values are: #{VALID_TARGET_TYPES.join(', ')}"
        end

        # Map target_type to the IssueQuery type parameter:
        #   "issue"                          → "issues" (issues index only)
        #   "pull-request"                   → "pr" (pull-requests index only)
        #   "issue,pull-request" / "pull-request,issue" → nil (issues-search alias covering both indices)
        es_type = case @target_type
        when "pull-request" then "pr"
        when "issue,pull-request", "pull-request,issue" then nil
        else "issues"
        end

        opts.merge!(
          type: es_type,
          repo_id: @issue.repository_id,
        )

        super(opts, &block)
      end

      def query_document
        doc = build_query
        doc[:from]    = offset
        doc[:size]    = per_page
        doc[:_source] = source_fields
        doc
      end

      def body_query
        return @body_query if defined?(@body_query)

        ## we truncate the body to 256 characters to avoid hitting timeout errors
        @body_query = @issue.body.to_s.truncate(SEARCH_CONTEXT_MAX_LENGTH, omission: "")

        @body_query
      end

      # Increase timeout a bit since semantic queries can be a bit slower.
      # ES timeout must be less than HTTP timeout to allow partial results.
      def default_query_params
        super.merge(timeout: "2000ms", read_timeout: 3.5) # 1.5s gap for partial results
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def build_query
        retrievers = build_knn_retrievers

        {
          retriever: {
            linear: {
              retrievers: retrievers,
            }
          },
        }
      end

      def build_knn_retrievers
        embedding_vector = fetch_embedding_vector(issue_search_phrase)

        knn_queries = []

        if @issue.title.present?
          knn_queries << knn_retriever("title_dense_vector", embedding_vector, TITLE_SEMANTIC_WEIGHT)
        end

        if body_query.present?
          knn_queries << knn_retriever("body_dense_vector", embedding_vector, BODY_SEMANTIC_WEIGHT)
        end

        knn_queries
      end

      def knn_retriever(field, query_vector, weight)
        {
          retriever: {
            standard: {
              query: {
                bool: {
                  must: [
                    IssueSemanticHelper.build_knn_clause(
                      field,
                      query_vector: query_vector,
                      k: SIMILAR_KNN_K,
                      num_candidates: SIMILAR_KNN_CANDIDATES,
                      similarity: @threshold,
                      filter: filter
                    )
                  ]
                }
              }
            }
          },
          weight: weight
        }
      end

      def filter
        {
          bool: {
            must: {
              term: {
                repo_id: @issue.repository_id
              }
            },
            must_not: {
              term: {
                issue_id: @issue.id
              }
            }
          }
        }
      end

      # Override to route PR queries to the dedicated experiment index when
      # configured. The dedicated index contains semantic vectors for PRs;
      # the standard pull-requests index does not.
      def index_for_type_param
        dedicated_index = dedicated_pr_index_name
        return super unless dedicated_index

        index_name = index_name_for_type_param
        case index_name
        when "pull-requests"
          Elastomer::Indexes::Issues.searcher(dedicated_index)
        when "issues-search"
          # Combined query: search issues index + dedicated PRs index.
          issues_index_name = "issues#{Elastomer.env.postfix}"
          cluster = ::Elastomer.router.cluster_for_index(issues_index_name)
          Elastomer::Indexes::Issues.searcher("#{issues_index_name},#{dedicated_index}", cluster)
        else
          super
        end
      end

      # Returns the dedicated PR index name when configured,
      # or nil to fall back to the standard index.
      def dedicated_pr_index_name
        name = GitHub.es_semantic_experiment_prs_index_name
        name.presence
      end

      # Search for semantically similar issues and/or pull requests to the provided issue.
      #
      # Returns an array of SimilarIssueResult structs containing:
      # - issue: The similar Issue object (for PRs, this is the Issue backing the PR)
      # - score: The similarity score (Float), or nil if unavailable
      #
      # The score is a composite value from Elasticsearch's linear retriever combining:
      # - Title KNN similarity (weight: 2.0)
      # - Body KNN similarity (weight: 1.75)
      # Higher scores indicate greater similarity.
      #
      # target_type controls which document types are searched:
      # - "issue" (default): only issues
      # - "pull-request": only pull requests
      # - "issue,pull-request": issues and pull requests
      sig do
        params(
          issue: Issues::IIssue,
          current_user: T.nilable(::User),
          threshold: T.nilable(Float),
          per_page: T.nilable(Integer),
          page: T.nilable(Integer),
          context: T.nilable(String),
          target_type: T.nilable(String),
          kwargs: T::Hash[Symbol, T.untyped]
        ).returns(T::Array[SimilarIssueResult])
      end
      def self.find_similar_to(issue:, current_user:, threshold: nil, per_page: nil, page: nil, context: nil, target_type: nil, **kwargs)
        # Validate required parameters
        return [] if issue.nil?

        begin
          query = self.new(issue:, current_user:, threshold:, per_page: per_page, page: page, context:, target_type:, **kwargs)
          search_result = query.execute.results

          # Handle case where search returns nil or empty results
          return [] if search_result.nil? || search_result.empty?

          search_result.map { |result| SimilarIssueResult.new(issue: result["_model"], score: result["_score"]) }
        rescue *RESCUABLE_ERROR_TYPES => e
          Failbot.report(e)
          []
        end
      end

      private

      def issue_search_phrase
        parts = []
        parts << @issue.title.to_s if @issue.title.present?
        parts << @issue.body.to_s if @issue.body.present?

        sanitized = ::Search.clean_and_sanitize(parts.join(" ").squish)

        sanitized.truncate(SEARCH_CONTEXT_MAX_LENGTH, omission: "")
      end
    end
  end
end
