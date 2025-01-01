# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class ConditionalIssueSemanticQuery < ConditionalIssueQuery
      include IssueSemanticHelper

      sig { params(qualifier: ParsletQuery::QueryQualifier, search_in_fields: T::Array[String]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def qualifier_to_query(qualifier, search_in_fields)
        escaped_query = escape_query(qualifier.query)

        has_quoted_text_term = escaped_query.include?('"')

        # phrase_slop of zero means that the tokens in a matching document have to appear in the exact order
        # of the terms in an ElasticSearch phrase (characters surrrounded by double quotes) in the query input
        phrase_slop = has_quoted_text_term ? 0 : DEFAULT_PHRASE_SLOP_VALUE

        # "texty" analyzer has to be used for exact queries because some characters can produce a different set of tokens
        # when processed by "texty_search"
        analyzer = has_quoted_text_term ? "texty" : "texty_search"

        function_query = if use_semantic_query?
          build_semantic_function_query(escaped_query)
        else
          {
            query_string: {
              query: escaped_query,
              fields: query_fields_to_search(search_in_fields),
              phrase_slop: phrase_slop,
              default_operator: "AND",
              analyzer: analyzer,
            }
          }
        end

        query = {
          function_score: {
            query: function_query,
            score_mode: "sum",
            functions: [
              {
                exp: {
                  created_at: {
                    scale: "42d",
                    decay: 0.5,
                  }
                }
              },
              {
                exp: {
                  updated_at: {
                    scale: "84d",
                    decay: 0.5,
                  }
                }
              },
              {
                filter: { term: { state: "open" } },
                weight: 2,
              },
            ],
          }
        }

        # when the user query doesn't specify an `in` qualifier we look for potential commit SHAs and issue numbers
        # if we find them then we add clauses to look for those explicitly
        # if escape_wildcards parameter is false we need to strip the query off wildcards
        # before trying to match it with commit SHA or issue number
        query_without_wildcards = @escape_wildcards ? escape_query(qualifier.query) : qualifier.query.gsub(/[\*\?]/, "")

        commit_sha_clauses = search_in_fields.empty? ? commit_sha(query_without_wildcards) : []
        number_clauses = search_in_fields.empty? || @force_issue_number_terms || search_in_fields.include?("number") ? issue_number(query_without_wildcards) : []
        more_clauses = commit_sha_clauses + number_clauses

        if more_clauses.any?
          more_clauses.unshift query
          query = { bool: { should: more_clauses } }
        end

        query
      end
    end
  end
end
