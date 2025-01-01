# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      class FieldValueQualifier < Qualifier
        sig { override.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def compile(context)
          field = T.let(context.field_by_query_slug[slug], T.nilable(MemexProjectColumn::Field::Base))
          if field.present?
            # Wrap with 'bool' 'must' to ensure that it properly ANDs all field query fragments for the Elasticsearch query.
            {
              bool: {
                must: [
                  field.query_fragment(values:, is_negated: negated?, context:)
                ]
              }
            }
          else
            {}
          end
        end
      end
    end
  end
end
