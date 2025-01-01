# typed: strict
# frozen_string_literal: true

module Search
  module Responses
    class MemexProjectItemResponse < CursorPaginationResponse
      include GitHub::Memoizer
      include SharedMemexProjectItemResponseDependency

      # TODO: Update this to use the actual type of the result objects
      # https://github.com/github/projects-backend/issues/213
      Elem = type_member { { fixed: T.untyped } }
      Model = type_member { { fixed: MemexProjectItem } }

      sig { params(response: T.untyped, opts: T::Hash[T.untyped, T.untyped]).void }
      def initialize(response, opts = {})
        super(response, opts)
        initialize_response(aggregations, opts)
      end

      # Returns all memex project items from the search response regardless of grouping
      sig { override.returns(T::Array[Model]) }
      memoize def models
        ids = result_enumerator.map { |r| r.dig("_source", "database_id") }
        items = MemexProjectItem.where(id: ids).order(Arel.sql("FIELD(id, #{ids.join(',')})")).to_a

        if @remove_spam && @viewer
          GitHub::PrefillAssociations.prefill_batch_method(items, :is_content_spammy?, @viewer)
          items.reject! { |item| item.is_content_spammy?(@viewer) }
        end

        item_by_id = items.index_by(&:id)

        result_enumerator.each do |result|
          next unless item = item_by_id[result.dig("_source", "database_id")]
          sort = result.dig("sort")
          item.sort_values = sort
          item.cursor = Search::Responses::PropertyEncoder.encode(result.dig("sort"))
        end

        items
      end

      # Returns all memex project item ids from the search response regardless of grouping
      # These are not redacted for spammy user checks
      sig { returns(T::Array[Integer]) }
      def model_ids
        result_enumerator.map { |r| r.dig("_source", "database_id") }
      end

      sig { returns(T::Boolean) }
      def total_is_approximate?
        total_relation != :eq
      end

      sig { returns(T::Boolean) }
      def grouped?
        false
      end

      sig { returns(T::Enumerator[T::Hash[T.untyped, T.untyped]]) }
      private def result_enumerator
        Enumerator.new do |output|
          results.each { |r| output << r }
        end
      end
    end
  end
end
