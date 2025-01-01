# typed: strict
# frozen_string_literal: true

# `MemexProjectItem::Title` is a wrapper for the title of a `MemexProjectItem` within a `MemexProject`.
#
# It implements the `MemexProjectColumn::Interface::Serializable` interface, allowing it to be serialized into a hash
# format suitable for JSON representation and CSV export.
#
# Currently `MemexProjectItem::Title` is only used in `MemexProjectColumn::Field::Title` as a way to satisfy the
# `MemexProjectColumn::Interface::Serializable` interface.
#
# `MemexProjectItem::Title` can be initialized with a denormalized title value directly from `MemexProjectColumnValue`
# where the hash will contain string keys, or it can be initialized directly from the underlying content model's
# `memex_denormalized_title_value` method. See `Issue#memex_denormalized_title_value` as an example.
class MemexProjectItem
  class Title
    include MemexProjectColumn::Interface::Serializable

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    attr_reader :title

    sig { params(title: T::Hash[T.untyped, T.untyped]).void }
    def initialize(title)
      @title = title
    end

    sig { override.returns(MemexProjectColumn::Interface::Serializable::JSONValue) }
    def memex_column_hash
      title
    end

    sig { override.returns(String) }
    def csv_column_value
      # Denormalized title values have string hash keys, while non-denormalized title values have symbol hash keys.
      title.dig("title", "raw") || title.dig(:title, :raw)
    end
  end
end
