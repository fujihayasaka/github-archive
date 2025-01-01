# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Mapping
      # This class builds up an Elasticsearch schema ("mapping") for the MemexProjectItem document type from the
      # smaller building blocks in the `Mapping::FieldDataTypes` module.
      class MemexProjectItem
        extend T::Sig

        FULL_TEXT_SEARCH_FIELDS = T.let(%w(future_searchable_text), T::Array[String])

        sig { params(mapping: FieldDataTypes::Object, routing: T.nilable(Routing)).void }
        def initialize(mapping, routing: nil)
          @mapping = mapping
          @_routing = T.let(routing || Routing.new(required: true), Routing)
        end

        # Hide the constructor; consumers should use the `create` method instead.
        private_class_method :new

        sig { params(field_specific_properties: T::Hash[Symbol, FieldDataType]).returns(MemexProjectItem) }
        def self.create(field_specific_properties)
          self.new(
            FieldDataTypes::Object.new(
              dynamic: Dynamic::Strict,
              properties: {
                database_id: FieldDataTypes::Long.new,
                memex_project_id: FieldDataTypes::Long.new,
                content: FieldDataTypes::Object.new(
                  properties: {
                    id: FieldDataTypes::Long.new,
                    type: FieldDataTypes::Keyword.new,
                    state: FieldDataTypes::Keyword.new,
                    state_reason: FieldDataTypes::Keyword.new,
                    is_draft: FieldDataTypes::Boolean.new,
                    number: FieldDataTypes::Integer.new(copy_to: Elastomer::Interfaces::Mapping::MemexProjectItem::FULL_TEXT_SEARCH_FIELDS),
                    repository_id: FieldDataTypes::Long.new
                  }
                ),
                virtual_priority: FieldDataTypes::Keyword.new,
                future_searchable_text: FieldDataTypes::KeywordMultiField.new(
                  analyzer: Analyzer::SearchAsYouType,
                  search_analyzer: Analyzer::SearchAsYouTypeKeyword
                ),
                archived_at: FieldDataTypes::Date.new,
                created_at: FieldDataTypes::Date.new,
                updated_at: FieldDataTypes::Date.new,
                field_values: FieldDataTypes::Object.new(
                  custom_field_type: FieldDataTypeName::Nested,
                  properties: {
                    field_slug: FieldDataTypes::Text.new,
                    field_type: FieldDataTypes::Text.new,
                    field_id: FieldDataTypes::Long.new,
                  }.merge(field_specific_properties)
                )
              }
            )
          )
        end

        sig { returns(T::Hash[T.untyped, T.untyped]) }
        def to_hash
          @mapping.to_hash.merge({ _routing: @_routing.to_hash })
        end
      end
    end
  end
end
