# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module GraphQL
        class TemplateIndex
          # Query for fetching Index Cards associated with a Template Index entry, with optional filtering and
          # ordering.
          #
          CardsQuery = T.let(Client.parse(<<-'GRAPHQL'), T.untyped)
            query($id: String!, $locale: String!, $limit: Int, $skip: Int, $order: [TemplateIndexCardsCollectionOrder], $filters: IndexCardFilter) {
              templateIndex(id: $id, locale: $locale) {
                cardsCollection(limit: $limit, skip: $skip, order: $order, where: $filters) {
                  total
                  items {
                    __typename
                    sys {
                      id
                    }
                    title
                    card {
                      __typename
                      sys {
                        id
                      }
                      href
                      heading
                      description {
                        json
                      }
                      image {
                        ...Site::Contentful::Marketing::GraphQL::Asset::Fragment
                      }
                    }
                  }
                }
              }
            }
          GRAPHQL

          # Type alias to represent the filter structure for querying Index Cards. This isn't a complete
          # representation of all possible filters, but includes the ones we currently use. This will help to ensure
          # that the filters we construct match the expected structure.

          sig { params(id: String, locale: String).void }
          def initialize(id:, locale: "en-US")
            @id = id
            @locale = locale
          end

          sig do
            params(
              limit: T.nilable(Integer),
              skip: T.nilable(Integer),
              order: T.nilable(CardsCollectionOrder),
              filters: T.nilable(IndexCardFilter),
            ).returns({
              total: Integer,
              items: T::Array[T::Hash[String, T.untyped]]
            })
          end
          def cards(limit: 12, skip: 0, order: nil, filters: nil)
            variables = { id: @id, locale: @locale, limit: limit, skip: skip, order: order&.to_s, filters: filters&.serialize }.compact

            response = Client.query(CardsQuery, variables:)
            if response.errors.any?
              return { total: 0, items: [] }
            end

            total = response.data&.template_index&.cards_collection&.total || 0
            items = (response.data&.template_index&.cards_collection&.items || []).map do |index_card|
              EntryAdapter.new(
                typename: index_card.__typename,
                data: index_card.to_h.except("__typename")
              ).call
            end

            { total:, items: }
          end
        end
      end
    end
  end
end
