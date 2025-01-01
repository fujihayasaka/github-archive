# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      # Methods shared by ContentQualifier and StateQualifier
      module StateValueHelpers
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
                  { term: { "content.is_draft" => { value: true } } },
                  { term: { "content.state" => { value: "open" } } }
                ]
              }
            }
          ]
        end

        sig { params(content_state: String).returns(T::Hash[T.untyped, T.untyped]) }
        private def compile_content_state_query(content_state:)
          { term: { "content.state" => { value: content_state } } }
        end
      end
    end
  end
end
