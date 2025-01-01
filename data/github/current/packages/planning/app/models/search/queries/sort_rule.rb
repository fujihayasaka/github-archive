# typed: strict
# frozen_string_literal: true

module Search
  module Queries
    class SortRule
      extend T::Sig

      class Order < T::Enum
        enums do
          Asc = new
          Desc = new
        end
      end

      class SortMissingValues < T::Enum
        enums do
          First = new("_first")
          Last = new("_last")
        end
      end

      # https://www.elastic.co/guide/en/elasticsearch/reference/current/sort-search-results.html#_sort_order
      DEFAULT_ORDER_NOT_SCORE = Order::Asc
      DEFAULT_ORDER_SCORE = Order::Desc
      # https://www.elastic.co/guide/en/elasticsearch/reference/current/sort-search-results.html#_missing_values
      DEFAULT_MISSING = SortMissingValues::Last

      Configuration = T.type_alias { T::Hash[T.untyped, T.untyped] }

      sig { returns(String) }
      attr_reader :field

      sig { params(field: T.any(String, Symbol), configuration: T.any(String, Configuration)).void }
      def initialize(field, configuration)
        @field = T.let(field.to_s, String)
        @configuration = T.let(
          configuration.is_a?(String) ? { order: configuration } : configuration.deep_symbolize_keys,
          Configuration
        )
        @order = T.let(
          Order.try_deserialize(@configuration[:order]) || default_sort_order,
          Order
        )
        @sort_missing_values = T.let(
          SortMissingValues.try_deserialize(@configuration[:missing]) || DEFAULT_MISSING,
          SortMissingValues
        )
      end

      sig do
        params(hash: T::Hash[T.any(String, Symbol), T.any(String, Configuration)])
        .returns(SortRule)
      end
      def self.from_hash(hash)
        field = T.must(hash.keys.first)
        configuration = T.must(hash.values.first)
        SortRule.new(field, configuration)
      end

      sig { returns(Order) }
      def default_sort_order
        field == "_score" ? DEFAULT_ORDER_SCORE : DEFAULT_ORDER_NOT_SCORE
      end

      # Sorting can be script-based, in which case the field is "_script".
      # Script-based sorts do not support the "missing" parameter.
      sig { returns(Configuration) }
      def to_hash
        sort_props = { order: order.serialize }
        sort_props[:missing] = sort_missing_values.serialize unless field == "_script"
        { field.to_sym => configuration.merge(sort_props) }
      end

      # Inverting the sort order allows paging backwards
      # via Elasticsearch's search_after feature.
      # See https://github.com/elastic/elasticsearch/issues/29449
      sig { void }
      def invert!
        self.order = order == Order::Asc ? Order::Desc : Order::Asc
        self.sort_missing_values = sort_missing_values == SortMissingValues::Last ? SortMissingValues::First : SortMissingValues::Last
      end

      private

      sig { returns(Order) }
      attr_accessor :order

      sig { returns(SortMissingValues) }
      attr_accessor :sort_missing_values

      sig { returns(Configuration) }
      attr_reader :configuration
    end
  end
end
