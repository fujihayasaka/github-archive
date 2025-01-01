# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      # Represents a free text query entered by the user on a Memex project.
      # Takes in a full text search query created from Search::Memex::QueryParser and compiles it into an Elasticsearch query fragment.
      class FullTextQuery < Node
        SPECIAL_ISSUE_NUMBER_QUERY_SYNTAX_RE = /\A#\d+\z/

        sig { returns(String) }
        attr_accessor :query_string

        sig { params(query_string: String).void }
        def initialize(query_string)
          @query_string = query_string
        end

        # Converts a query_string representing a full text search item into an Elasticsearch query fragment.
        # ex. "part of my issue title" => {:bool=>{:must=>[{:match=>{:future_searchable_text=>"part of my issue title"}}]}}
        sig { override.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def compile(context)
          boolean_text_query_clauses = if @query_string.match?(SPECIAL_ISSUE_NUMBER_QUERY_SYNTAX_RE)
            {
              must: [
                {
                  term: { "future_searchable_text.keyword" => @query_string[1..-1] }
                }
              ]
            }
          else
            {
              should: [
                {
                  match: {
                    future_searchable_text: {
                      query: @query_string,
                      operator: "AND",
                    },
                  },
                },
                { term: { "future_searchable_text.keyword" => @query_string } }
              ],
              minimum_should_match: 1
            }
          end

          { bool: boolean_text_query_clauses }
        end
      end
    end
  end
end
