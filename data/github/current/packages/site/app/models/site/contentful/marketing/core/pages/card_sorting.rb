# typed: strict
# frozen_string_literal: true

module Site
  module Contentful
    module Marketing
      module Core
        module Pages
          module CardSorting
            CardType = T.type_alias { T::Hash[String, T.untyped] }

            SORT_OPTION_MAP = T.let({
              "Date (ascending)" => :date_asc,
              "Date (descending)" => :date_desc,
            }.freeze, T::Hash[String, Symbol])

            sig { params(cards: T::Array[CardType]).returns(T::Array[CardType]) }
            def date_asc(cards)
              cards.sort_by { |card| parse_card_date(card) }
            end

            sig { params(cards: T::Array[CardType]).returns(T::Array[CardType]) }
            def date_desc(cards)
              date_asc(cards).reverse
            end

            private

            sig { params(card: CardType).returns(Time) }
            def parse_card_date(card)
              date_str = card.dig("fields", "date")
              return Time.at(0) unless date_str.present?
              begin
                Time.parse(date_str)
              rescue ArgumentError
                Time.at(0)
              end
            end
          end
        end
      end
    end
  end
end
