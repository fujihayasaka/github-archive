# typed: strict
# frozen_string_literal: true

# `MemexProjectItem::Milestone` is a wrapper for a denormalized Milestone hash belonging to a `MemexProjectItem`
# within a `MemexProject`.
#
# It implements the `MemexProjectColumn::Interface::Serializable` interface, allowing it to be serialized into a hash
# format suitable for JSON representation and CSV export.
#
# Currently `MemexProjectItem::Milestone` is only used in `MemexProjectColumn::Field::Milestone` as a way to satisfy
# the `MemexProjectColumn::Interface::Serializable` interface.
class MemexProjectItem
  class Milestone
    include MemexProjectColumn::Interface::Serializable

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    attr_reader :milestone

    sig { params(milestone: T::Hash[T.untyped, T.untyped]).void }
    def initialize(milestone)
      @milestone = milestone
    end

    sig { override.returns(MemexProjectColumn::Interface::Serializable::JSONValue) }
    def memex_column_hash
      milestone
    end

    sig { override.returns(String) }
    def csv_column_value
      milestone[:title]
    end
  end
end
