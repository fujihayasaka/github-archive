# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      class FieldValueQualifier < Qualifier
        sig { override.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def compile(context)
          field = queryable_field(context)
          if field
            field.query_fragment(values:, is_negated: negated?, context:)
          else
            # Fall back to full text search if the field is not queryable
            Nodes::FullTextQuery.new(query_string).compile(context)
          end
        end

        sig { params(context: Search::Memex::Context).returns(T.nilable(MemexProjectColumn::Field::Base)) }
        private def queryable_field(context)
          field = context.field_by_query_slug[slug]
          field.present? && field.class.queryable? ? field : nil
        end
      end
    end
  end
end
