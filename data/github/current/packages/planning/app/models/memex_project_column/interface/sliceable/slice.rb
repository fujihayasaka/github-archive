# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Sliceable
  class Slice < T::Struct
    include GitHub::Memoizer

    const :slice_id, String
    const :slice_value, String, default: MISSING_VALUE_GROUP_KEY
    const :slice_metadata, T.nilable(T::Hash[T.untyped, T.untyped])
    const :item_count, Integer, default: 0
    prop :metadata, T.nilable(MemexProjectColumn::IDataSource)

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    def to_hash
      {
        sliceId: slice_id,
        sliceValue: slice_value,
        sliceMetadata: slice_metadata,
        totalCount: total_count.to_hash,
      }.compact.stringify_keys
    end

    sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
    memoize def slice_metadata
      metadata&.memex_project_column_value&.to_permitted_hash&.transform_keys { |key| key.to_s.camelize(:lower) }
    end

    sig { returns(Search::Responses::TotalCount) }
    memoize def total_count
      Search::Responses::TotalCount.new(
        value: item_count,
        is_approximate: false,
      )
    end
  end
end
