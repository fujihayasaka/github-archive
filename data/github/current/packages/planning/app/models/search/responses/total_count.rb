# typed: strict
# frozen_string_literal: true

# Class that represents the total number of items in the underlying collection of items
# independent of page size. This value may be approximate if the collection too large
# for Elasticsearch to count efficiently.
module Search
  module Responses
    class TotalCount < T::Struct
      const :value, Integer
      const :is_approximate, T::Boolean

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def to_hash
        {
          value: value,
          isApproximate: is_approximate
        }
      end
    end
  end
end
