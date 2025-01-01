# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      class ReasonQualifier < Qualifier
        sig { override.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def compile(context)
          return {} unless values.present?

          should_clauses = values.map do |closed_reason|
            case closed_reason.downcase
            when "completed"
              {
                bool: {
                  must: [
                    { term: { "content.state" => "closed" } },
                    { bool: { must_not: { exists: { field: "content.state_reason" } } } },
                  ]
                }
              }
            when "not planned", "not-planned"
              {
                bool: {
                  must: [
                    { term: { "content.state" => "closed" } },
                    { term: { "content.state_reason" => "not_planned" } },
                  ]
                }
              }
            when "reopened"
              {
                bool: {
                  must: [
                    { term: { "content.state" => "open" } },
                    { term: { "content.state_reason" => "reopened" } },
                  ]
                }
              }
            end
          end

          result = { bool: { should: should_clauses, minimum_should_match: 1 } }
          result = { bool: { must_not: result } } if negated?
          result
        end
      end
    end
  end
end
