# typed: strict
# frozen_string_literal: true

# Class that represents pagination metadata for collections of items.
# This is designed to mimic GraphQL pagination: https://graphql.org/learn/pagination/.
module Search
  module Responses
    class PageInfo < T::Struct

      const :start_cursor, T.nilable(String)
      const :end_cursor, T.nilable(String)
      const :has_next_page, T::Boolean, default: false
      const :has_previous_page, T::Boolean, default: false

      sig { returns(T::Hash[T.untyped, T.untyped]) }
      def to_hash
        {
          start_cursor:,
          end_cursor:,
          has_next_page:,
          has_previous_page:,
        }
        .compact
      end
    end
  end
end
