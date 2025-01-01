# typed: true
# frozen_string_literal: true

require "set"

module Search
  module Queries
    class IssueSemanticQuery < IssueQuery
      include IssueSemanticHelper

      def query_doc
        return if escaped_query.empty?

        escaped_query_input = @escape_wildcards ? "#{escaped_query}" : "#{escaped_query_with_search_modifiers}"
        function_query = if use_semantic_query?
          build_semantic_function_query(escaped_query_input)
        else
          {
            query_string: {
              query: escaped_query_input,
              fields: query_fields,
              phrase_slop: 10,
              default_operator: "AND",
              analyzer: "texty_search",
            }
          }
        end

        q = { function_score: {
          query: function_query,
          score_mode: "sum",
          functions: [
            { exp: { created_at: {
              scale: "42d",
              decay: 0.5,
            } } },
            { exp: { updated_at: {
              scale: "84d",
              decay: 0.5,
            } } },
            {
              filter: { term: { state: "open" } },
              weight: 2,
            },
          ],
        } }

        # when the user query doesn't specify an `in` qualifier we look for potential commit SHAs and issue numbers
        # if we find them then we add clauses to look for those explicitly
        # if escape_wildcards parameter is false we need to strip the query off wildcards
        # before trying to match it with commit SHA or issue number
        query_without_wildcards = @escape_wildcards ? escaped_query : query.gsub(/[\*\?]/, "")

        commit_sha_clauses = search_in.empty? ? commit_sha(query_without_wildcards) : []
        number_clauses = search_in.empty? || @force_issue_number_terms || search_in.include?("number") ? issue_number(query_without_wildcards) : []
        more_clauses = commit_sha_clauses + number_clauses

        if more_clauses.any?
          more_clauses.unshift q
          q = { bool: { should: more_clauses } }
        end

        q
      end
    end  # IssueSemanticQuery
  end  # Queries
end  # Search
