# typed: strict
# frozen_string_literal: true

module Site::Contentful::Marketing::GraphQL
  class TemplateIndex
    # Enum to represent the possible ordering options for the cards collection.
    class CardsCollectionOrder < T::Enum
      enums do
        DATE_ASC = new(:date_ASC)
        DATE_DESC = new(:date_DESC)
      end

      sig { params(value: T.nilable(Symbol)).returns(CardsCollectionOrder) }
      def self.from(value)
        options = {
          date_asc: DATE_ASC,
          date_desc: DATE_DESC,
        }

        # Default to DATE_ASC if the provided value is not recognized
        options.fetch(value, DATE_ASC)
      end

      sig { returns(String) }
      def to_s
        serialize.to_s
      end
    end
  end
end
