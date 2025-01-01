# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      class FieldValuePresenceQualifier < Qualifier
        include DependenciesValueHelpers

        sig { override.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def compile(context)
          fragments = T.let([], T::Array[T::Hash[T.untyped, T.untyped]])
          should_clauses = T.let([], T::Array[T::Hash[T.untyped, T.untyped]])

          # Handle dependencies fields separately because they are properties of the content object
          # rather than proper project column fields.
          values.select do |value|
            dependencies_search_enabled?(context) && DEPENDENCIES_FIELDS.include?(value)
          end.each do |query_value|
            dependencies_existence_fragment = compile_dependencies_existence_query(query_value: query_value)
            next if dependencies_existence_fragment.nil?
            fragments << dependencies_existence_fragment
          end

          matching_fields(context).each_with_object(fragments) do |field, result|
            existence_fragment = field.existence_fragment
            next if existence_fragment.blank?
            result << existence_fragment
          end

          should_clauses = fragments.map do |fragment|
            { bool: negated? ? { must_not: [fragment] } : { must: [fragment] } }
          end

          # 'has:field1,field2' translates to 'has field1 value OR has field2 value'
          # 'has:field1 has:field2' translates to 'has field1 value AND has field2 value'.
          if should_clauses.length > 1
            {
              bool: { should: should_clauses, minimum_should_match: 1 }
            }
          else
            should_clauses.first || {}
          end
        end

        sig { params(context: Search::Memex::Context).returns(T::Array[MemexProjectColumn::Field::Base]) }
        private def matching_fields(context)
          result = values.reject do |value|
            # Dependencies fields are handled separately
            dependencies_search_enabled?(context) && DEPENDENCIES_FIELDS.include?(value)
          end.map do |value|
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
