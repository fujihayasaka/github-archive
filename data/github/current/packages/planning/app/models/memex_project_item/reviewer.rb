# typed: strict
# frozen_string_literal: true

# `MemexProjectItem::Reviewer` is a wrapper for a reviewer belonging to a `MemexProjectItem` within a
# `MemexProject`.
#
# It implements the `MemexProjectColumn::Interface::Serializable` interface, allowing it to be serialized into a hash
# format suitable for JSON representation and CSV export.
#
# Currently `MemexProjectItem::Reviewer` is only used in `MemexProjectColumn::Field::Reviewers` as a way to satisfy
# the `MemexProjectColumn::Interface::Serializable` interface.
class MemexProjectItem
  class Reviewer
    include MemexProjectColumn::Interface::Serializable

    sig { returns(T::Hash[T.untyped, T.untyped]) }
    attr_reader :reviewer

    sig { params(reviewer: T::Hash[T.untyped, T.untyped]).void }
    def initialize(reviewer)
      @reviewer = reviewer
    end

    sig { override.returns(MemexProjectColumn::Interface::Serializable::JSONValue) }
    def memex_column_hash
      reviewer
    end

    sig { override.returns(String) }
    def csv_column_value
      reviewer[:reviewer][:name]
    end
  end
end
