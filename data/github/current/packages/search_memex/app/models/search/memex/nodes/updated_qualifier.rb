# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      # This class implements support for `updated` qualifier, which is standard across product domains.
      # This is in contrast to the legacy `last-updated` qualifier implemented in `LastUpdatedQualifier`.
      class UpdatedQualifier < Qualifier
        include ElasticsearchDateQueryHelper

        sig { override.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def compile(context)
          should_clauses = values.map do |value|
            date_query(field_path: "updated_at", date_value: value, context:)
          end

          bool_clause = if negated?
            { must_not: should_clauses }
          else
            { should: should_clauses, minimum_should_match: 1 }
          end

          { bool: bool_clause }
        end
      end
    end
  end
end
