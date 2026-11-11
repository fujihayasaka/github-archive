# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class SemanticSimilarIssueQuery < IssueQuery
      include T::Sig

      SEARCH_CONTEXT_MAX_LENGTH = 256
      DEFAULT_SEMANTIC_SIMILAR_ISSUE_THRESHOLD = 0.8
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

      sig { returns(::Issues::IIssue) }
      attr_reader :issue

      sig { returns(Float) }
      attr_reader :threshold

      # Construct a SemanticSimilarIssueQuery.
      # The query will search for issues that are semantically similar
      # to the provided issue.
      #
      # opts - The options Hash.
      #   :issue  - The candidate issue
      #   :threshold - The minimum score threshold for similarity (default: 0.8)
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

        opts.merge!(
          type: "issues",
          repo_id: @issue.repository_id,
        )

        super(opts, &block)
      end

      def query_document
        doc = build_query
        doc[:from]    = offset
        doc[:size]    = per_page
        doc[:_source] = source_fields
        # commenting this out for now until we have a better undestanding of scoring behaviour
        # doc[:min_score] = normalised_threshold
        doc
      end

      def body_query
        return @body_query if defined?(@body_query)

        ## we truncate the body to 256 characters to avoid hitting timeout errors
        @body_query = @issue.body.to_s.truncate(SEARCH_CONTEXT_MAX_LENGTH, omission: "")

        @body_query
      end

      # Increase timeout a bit since semantic queries can be a bit slower.
      def default_query_params
        super.merge(timeout: "2000ms")
      end

      # Build the query instead of relying on query_doc because we don't want
      # to follow the usual structure of a query, and the filters need to
      # be embedded within the retriever queries.
      sig { returns(T::Hash[Symbol, T.untyped]) }
      def build_query
        {
          retriever: {
            linear: {
              retrievers: [
                semantic_retriever("title_dense_vector", @issue.title, TITLE_SEMANTIC_WEIGHT),
                semantic_retriever("body_dense_vector", body_query, BODY_SEMANTIC_WEIGHT),
              ].compact,
            }
          },
        }
      end

      def semantic_retriever(name, value, weight)
        return nil if value.blank?

        {
          retriever: {
            standard: {
              query: {
                bool: {
                  must: [{
                    semantic: {
                      field: name,
                      query: value
                    }
                  }],
                  filter: filter
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

      # Search for semantically similar issues to the provided issue.
      sig do
        params(
          issue: Issues::IIssue,
          current_user: T.nilable(::User),
          threshold: T.nilable(Float),
          per_page: T.nilable(Integer),
          page: T.nilable(Integer),
          kwargs: T::Hash[Symbol, T.untyped]
        ).returns(T::Array[T::Hash[Symbol, T.untyped]])
      end
      def self.find_similar_to(issue:, current_user:, threshold: nil, per_page: nil, page: nil, **kwargs)
        # Validate required parameters
        return [] if issue.nil?

        begin
          query = self.new(issue:, current_user:, threshold:, per_page: per_page, page: page, **kwargs)
          search_result = query.execute.results

          # Handle case where search returns nil or empty results
          return [] if search_result.nil? || search_result.empty?

          search_result.map { |result| result["_model"] }
        rescue *RESCUABLE_ERROR_TYPES => e # rubocop:todo Lint/GenericRescue
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
