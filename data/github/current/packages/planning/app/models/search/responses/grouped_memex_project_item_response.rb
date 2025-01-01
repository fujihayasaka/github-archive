# typed: strict
# frozen_string_literal: true

module Search
  module Responses
    class GroupedMemexProjectItemResponse < CursorPaginationResponse
      include GitHub::Memoizer
      include SharedMemexProjectItemResponseDependency

      # TODO: Update this to use the actual type of the result objects
      # https://github.com/github/projects-backend/issues/213
      Elem = type_member { { fixed: T.untyped } }
      Model = type_member { { fixed: MemexProjectItem } }

      # The first layer of grouping in the query response. Visually, this is horizontal
      # in a table view, but vertical in a board view.
      sig { returns(MemexProjectColumn::Interface::Groupable::PaginatedGroups) }
      attr_reader :primary_groups

      # The second layer of grouping in the query response. This is only supported on the board view
      # (for swimlanes), and is rendered horizontally.
      sig { returns(T.nilable(MemexProjectColumn::Interface::Groupable::PaginatedGroups)) }
      attr_reader :secondary_groups

      # The list of item arrays for each group and their corresponding group id and optional secondary group id.
      # When secondary grouping is not active, this list is 1:1 with primary groups.
      # When secondary grouping is active, this list aligns with the intersection of each primary/secondary pair.
      sig { returns(T::Array[MemexProjectColumn::Interface::Groupable::GroupedItems]) }
      attr_reader :grouped_items

      sig { params(response: T.untyped, opts: T::Hash[T.untyped, T.untyped]).void }
      def initialize(response, opts = {})
        @primary_groups = T.let(
          opts[:primary_groups] || MemexProjectColumn::Interface::Groupable::PaginatedGroups.new,
          MemexProjectColumn::Interface::Groupable::PaginatedGroups
        )
        opts.merge!(
          has_next_page: @primary_groups.has_next_page,
          has_previous_page: @primary_groups.has_previous_page
        )
        @secondary_groups = T.let(opts[:secondary_groups], T.nilable(MemexProjectColumn::Interface::Groupable::PaginatedGroups))
        @grouped_items = T.let(opts[:grouped_items] || [], T::Array[MemexProjectColumn::Interface::Groupable::GroupedItems])

        super(response, opts)
        initialize_response(aggregations, opts)

        @end_cursor = T.let(@primary_groups.end_cursor, T.nilable(String))
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
          item.cursor = Search::Responses::PropertyEncoder.encode(sort)
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
        true
      end

      sig { returns(T::Boolean) }
      def secondary_grouped?
        secondary_groups.present?
      end

      sig { returns(T::Enumerator[T::Hash[T.untyped, T.untyped]]) }
      private def result_enumerator
        Enumerator.new do |output|
          grouped_items.flat_map(&:paginated_items).each { |i| output << i }
        end
      end
    end
  end
end
