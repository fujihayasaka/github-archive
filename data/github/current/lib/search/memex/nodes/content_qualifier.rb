# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      class ContentQualifier < Qualifier
        sig { override.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def compile(context)
          result = T.let({}, T::Hash[T.untyped, T.untyped])

          values.each do |query_value|
            clause_key = clause_occurrence_type(query_value)

            case query_value
            when "draft"
              result[clause_key] = result.fetch(clause_key, []) + compile_draft_content_query
            when "issue"
              result[clause_key] = result.fetch(clause_key, []) << compile_content_type_query(content_type: "Issue")
            when "pr"
              result[clause_key] = result.fetch(clause_key, []) << compile_content_type_query(content_type: "PullRequest")
            when "open", "closed", "merged"
              result[clause_key] = result.fetch(clause_key, []) << compile_content_state_query(content_state: query_value)
            end
          end

          result[:minimum_should_match] = 1 if result[:should].present?

          { bool: result }
        end

        # Use the correct occurence type in the query clause for the given query value
        # See https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-bool-query.html for more details.
        sig { params(query_value: String).returns(Symbol) }
        private def clause_occurrence_type(query_value)
          if negated?
            :must_not
          elsif query_value == "draft"
            :should
          elsif values.one?
            :must
          else
            :should
          end
        end

        sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
        private def compile_draft_content_query
          # 'drafts' are either the DraftIssue content.type OR PullRequest's in 'draft' content.state
          # this is always going to be an OR query, either 'must_not' or 'should'
          [
            {
              bool: {
                must: [
                  { term: { "content.type" => { value: "DraftIssue" } } }
                ]
              }
            },
            {
              bool: {
                must: [
                  { term: { "content.type" => { value: "PullRequest" } } },
                  { term: { "content.is_draft" => { value: true } } }
                ]
              }
            }
          ]
        end

        sig { params(content_type: String).returns(T::Hash[T.untyped, T.untyped]) }
        private def compile_content_type_query(content_type:)
          { term: { "content.type" => { value: content_type } } }
        end

        sig { params(content_state: String).returns(T::Hash[T.untyped, T.untyped]) }
        private def compile_content_state_query(content_state:)
          { term: { "content.state" => { value: content_state } } }
        end
      end
    end
  end
end
