# typed: strict
# frozen_string_literal: true

module Site::Contentful::Marketing::GraphQL
  class TemplateIndex
    # Collection of structs to represent the filter structure for querying Index Cards. This isn't a complete
    # representation of all possible filters, but includes the ones we currently use. This will help to ensure
    # that the filters we construct match the expected structure.
    class IndexCardFilter < T::Struct
      class IndexFiltersCondition < T::Struct
        const :groupValue, String
        const :filterValue_in, T::Array[String]
      end

      class CardSearchCondition < T::Struct
        const :title_contains, T.nilable(String), default: nil
        const :description_contains, T.nilable(String), default: nil
      end

      # Filtering on the card's indexFilters field, which is a reference to IndexFilter entries.
      const :indexFilters, T.nilable(IndexFiltersCondition)
      # Filtering on the card's fields, specifically title or description.
      const :card, T.nilable(CardSearchCondition)
      # Logical AND of multiple filter conditions.
      const :AND, T.nilable(T::Array[IndexCardFilter])
      # Logical OR of multiple filter conditions.
      const :OR, T.nilable(T::Array[IndexCardFilter])

      # Helper method to create an IndexCardFilter for filtering by index filters.
      sig { params(group_value: String, filter_values: T::Array[String]).returns(IndexCardFilter) }
      def self.with_index_filters(group_value:, filter_values:)
        new(indexFilters: IndexFiltersCondition.new(groupValue: group_value, filterValue_in: filter_values))
      end

      # Helper method to create an IndexCardFilter for filtering by card fields.
      sig { params(title_contains: T.nilable(String), description_contains: T.nilable(String)).returns(T.nilable(IndexCardFilter)) }
      def self.with_card_search(title_contains: nil, description_contains: nil)
        condition_params = { title_contains:, description_contains: }.compact
        return if condition_params.empty?

        new(card: CardSearchCondition.new(**condition_params))
      end
    end
  end
end
