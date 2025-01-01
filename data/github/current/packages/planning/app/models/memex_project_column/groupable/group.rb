# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Groupable
  class Group < T::Struct
    extend T::Sig
    include GitHub::Memoizer

    const :group_by_key, Integer
    const :grouped_items_page_size, Integer
    const :group_value, String, default: MISSING_VALUE_GROUP_KEY
    const :top_hits_aggregation, T.nilable(T::Hash[T.untyped, T.untyped])
    const :item_count, T.nilable(Integer)
    prop :metadata, T.nilable(Metadata)

    sig { params(cursor: T.untyped, version: Symbol).returns(T.nilable(String)) }
    def self.encode_cursor(cursor, version: :v2)
      return unless cursor
      Platform::ConnectionWrappers::CursorGenerator.generate_cursor(cursor, version:)
    end

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def to_hash
      {
        group_value:,
        group_id:,
        group_metadata:,
        unnested_items: paginated_items,
        total_count: { value: total_count, is_approximate: approximate_total_count? },
        has_next_page:,
        end_cursor:,
      }.stringify_keys
    end

    sig { returns(String) }
    memoize def group_id
      T.must(self.class.encode_cursor([group_by_key, group_value]))
    end
    alias :primary_group_id :group_id

    sig { returns(T.nilable(String)) }
    memoize def secondary_group_id; end

    sig { returns(T::Array[T.untyped]) }
    memoize def paginated_items
      all_items.take(grouped_items_page_size)
    end

    sig { returns(T.nilable(String)) }
    memoize def start_cursor; end

    sig { returns(T.nilable(String)) }
    memoize def end_cursor
      self.class.encode_cursor(paginated_items.last&.dig("sort"))
    end

    sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
    memoize def group_metadata
      metadata&.group_metadata&.transform_keys { |key| key.to_s.camelize(:lower) }
    end

    sig { returns(Integer) }
    def total_count
      (total&.dig("value") || item_count).to_i
    end

    sig { returns(T::Boolean) }
    def approximate_total_count?
      relation = total&.fetch("relation", "eq")&.to_sym || :eq
      relation != :eq
    end

    sig { returns(T::Boolean) }
    def has_previous_page
      false
    end

    sig { returns(T::Boolean) }
    def has_next_page
      all_items.length > grouped_items_page_size
    end

    sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
    private def total
      top_hits_aggregation&.dig("hits", "total")
    end

    sig { returns(T::Array[T.untyped]) }
    memoize private def all_items
      top_hits_aggregation&.dig("hits", "hits").to_a
    end
  end
end
