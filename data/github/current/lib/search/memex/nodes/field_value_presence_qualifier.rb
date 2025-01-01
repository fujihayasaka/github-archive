# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      class FieldValuePresenceQualifier < Qualifier
        sig { override.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def compile(context)
          should_clauses = T.let([], T::Array[T::Hash[T.untyped, T.untyped]])

          matching_fields(context).each_with_object(should_clauses) do |field, result|
            existence_fragment = field.existence_fragment
            next if existence_fragment.blank?
            result << { bool: negated? ? { must_not: [existence_fragment] } : { must: [existence_fragment] } }
          end

          # 'has:field1,field2' translates to 'has field1 value OR has field2 value'
          # 'has:field1 has:field2' translates to 'has field1 value AND has field2 value'.
          if should_clauses.length > 1
            {
              bool: {
                must: {
                  bool: { should: should_clauses, minimum_should_match: 1 }
                }
              }
            }
          else
            should_clauses.first || {}
          end
        end

        sig { params(context: Search::Memex::Context).returns(T::Array[MemexProjectColumn::Field::Base]) }
        private def matching_fields(context)
          result = values.map do |value|
            # Match by query slug
            field = context.field_by_query_slug[value]
            # Or by case-insensitive field name
            # for backwards compatibility with client-side filtering
            field ||= context.field_by_query_slug.values.find do |f|
              f[:name].casecmp?(value)
            end
          end

          result.compact
        end
      end
    end
  end
end
