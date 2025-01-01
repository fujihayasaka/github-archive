# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Groupable
  class Group < T::Struct
    include GitHub::Memoizer

    GroupIdentifier = T.type_alias { T::Array[T.any(Integer, String)] }

    const :group_by_key, Integer
    const :group_value, String, default: MISSING_VALUE_GROUP_KEY
    const :top_hits_aggregation, T.nilable(T::Hash[T.untyped, T.untyped])
    const :item_count, Integer, default: 0
    prop :metadata, T.nilable(Metadata)

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def to_hash
      {
        group_value:,
        group_id:,
        group_metadata:,
        total_count: total_count.to_hash,
      }.stringify_keys
    end

    sig { returns(GroupIdentifier) }
    def unencoded_group_id
      [group_by_key, group_value]
    end

    sig { returns(String) }
    memoize def group_id
      T.must(Search::Responses::PropertyEncoder.encode(unencoded_group_id))
    end

    sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
    memoize def group_metadata
      metadata&.group_metadata&.transform_keys { |key| key.to_s.camelize(:lower) }
    end

    sig { returns(Search::Responses::TotalCount) }
    memoize def total_count
      Search::Responses::TotalCount.new(
        value: item_count,
        is_approximate: false,
      )
    end

    # A partial item document used to hydrate group metadata
    sig { returns(T.nilable(T::Hash[String, T.untyped])) }
    def partial_item_document
      top_hits_aggregation&.dig("hits", "hits", 0, "_source")
    end
  end
end
