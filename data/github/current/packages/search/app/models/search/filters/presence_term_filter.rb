# typed: strict
# frozen_string_literal: true

# An extension of TermFilter that is used to support the Search::Filter::NONE and Search::Filter::ANY
# special values. These values are mapped to `exists` and `missing` ES filters and are only used by
# a subset of terms.
module Search
  module Filters
    class PresenceTermFilter < TermFilter
      sig { params(values: T.untyped).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def build(values)
        return if values.blank?

        if values.include?(::Search::Filter::NONE)
          { bool: { must_not: { exists: { field: field } } } }
        elsif values.include?(::Search::Filter::ANY)
          { exists: { field: field } }
        else
          super(values)
        end
      end
    end
  end
end
