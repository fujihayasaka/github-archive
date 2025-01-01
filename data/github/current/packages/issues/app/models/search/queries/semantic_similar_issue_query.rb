# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class SemanticSimilarIssueQuery < IssueQuery
      include T::Sig

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

      # Each retriever multiplies the score by its weight, so we multiply the
      # threshold by the sum of the weights to get a normalised threshold.
      def normalised_threshold
        base = @threshold

        if use_simple_semantic_query?
          return base
        end

        if @issue.title.present?
          base += base * TITLE_SEMANTIC_WEIGHT
        end

        if body_query.present?
          base += base * BODY_SEMANTIC_WEIGHT
        end

        if use_hybrid_lexical_retriever? && (!@issue.title.blank? || !body_query.blank?)
          base += base * LEXICAL_WEIGHT
        end

        base
      end

      def body_query
        return @body_query if defined?(@body_query)

        ## we truncate the body to 256 characters to avoid hitting timeout errors
        @body_query = @issue.body.to_s.truncate(256, omission: "")

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
        return simple_semantic_query if use_simple_semantic_query?

        {
          retriever: {
            linear: {
              retrievers: [
                semantic_retriever("title_dense_vector", @issue.title, TITLE_SEMANTIC_WEIGHT),
                semantic_retriever("body_dense_vector", body_query, BODY_SEMANTIC_WEIGHT),
                hybrid_lexical_retriever
              ].compact,
            }
          },
        }
      end

      def simple_semantic_query
        should_clauses = []

        unless @issue.title.blank?
          should_clauses << {
            semantic: {
              field: "title_dense_vector",
              query: @issue.title
            }
          }
        end

        unless body_query.blank?
          should_clauses << {
            semantic: {
              field: "body_dense_vector",
              query: body_query
            }
          }
        end

        {
          query: {
            bool: {
              should: should_clauses
            }
          },
          filter: filter,
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

      def hybrid_lexical_retriever
        return nil unless use_hybrid_lexical_retriever?

        # Build match clauses for non-blank fields
        should_clauses = []

        unless @issue.title.blank?
          should_clauses << {
            match: {
              title: {
                query: @issue.title,
                operator: "or",
                minimum_should_match: "30%"
              }
            }
          }
        end

        unless body_query.blank?
          should_clauses << {
            match: {
              body: {
                query: body_query,
                operator: "or",
                minimum_should_match: "30%"
              }
            }
          }
        end

        return nil if should_clauses.empty?

        {
          retriever: {
            standard: {
              query: {
                bool: {
                  should: should_clauses,
                  filter: filter
                }
              }
            }
          },
          weight: LEXICAL_WEIGHT
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

      def use_simple_semantic_query?
        FeatureFlag.vexi.enabled?(:issues_semantic_similarity_simple_search, @current_user, default: false)
      end

      def use_hybrid_lexical_retriever?
        FeatureFlag.vexi.enabled?(:issues_semantic_similarity_hybrid_search, @current_user, default: false)
      end
    end
  end
end
