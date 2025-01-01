# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Groupable
  class GroupedItems < T::Struct
    include GitHub::Memoizer

    const :group_by_key, Integer
    const :group_value, String
    const :secondary_group_by_key, T.nilable(Integer)
    const :secondary_group_value, T.nilable(String)
    const :grouped_items_page_size, Integer
    const :top_hits_aggregation, T.nilable(T::Hash[T.untyped, T.untyped])

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def to_hash
      {
        group_id:,
        secondary_group_id:,
        group_value:,
        secondary_group_value:,
        page_info: page_info.to_hash,
      }.stringify_keys
    end

    sig { returns(String) }
    memoize def group_id
      T.must(Search::Responses::PropertyEncoder.encode([group_by_key, group_value]))
    end

    sig { returns(T.nilable(String)) }
    memoize def secondary_group_id
      return unless secondary_group_by_key && secondary_group_value
      Search::Responses::PropertyEncoder.encode([T.must(secondary_group_by_key), T.must(secondary_group_value)])
    end

    sig { returns(T::Array[T.untyped]) }
    memoize def paginated_items
      all_items.take(grouped_items_page_size)
    end

    sig { returns(T.nilable(String)) }
    memoize def start_cursor
      Search::Responses::PropertyEncoder.encode(paginated_items.first&.dig("sort"))
    end

    sig { returns(T.nilable(String)) }
    memoize def end_cursor
      Search::Responses::PropertyEncoder.encode(paginated_items.last&.dig("sort"))
    end

    sig { returns(Search::Responses::PageInfo) }
    memoize def page_info
      Search::Responses::PageInfo.new(
        has_previous_page:,
        has_next_page:,
        start_cursor:,
        end_cursor:,
      )
    end

    sig { returns(T::Boolean) }
    def has_previous_page
      false
    end

    sig { returns(T::Boolean) }
    def has_next_page
      all_items.length > grouped_items_page_size
    end

    sig { returns(T::Array[T.untyped]) }
    memoize private def all_items
      top_hits_aggregation&.dig("hits", "hits").to_a
    end
  end
end
