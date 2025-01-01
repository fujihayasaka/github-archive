# typed: strict
# frozen_string_literal: true

module Search
  module Responses
    class CursorPaginationResponse < ::Search::Results

      Elem = type_member { { fixed: T.untyped } }
      Model = type_member { { fixed: T.untyped } }

      sig { returns(T.nilable(String)) }
      attr_reader :end_cursor

      sig { returns(T.nilable(String)) }
      attr_reader :start_cursor

      sig { returns(T::Boolean) }
      attr_reader :has_next_page

      sig { returns(T::Boolean) }
      attr_reader :has_previous_page

      sig { params(response: T.untyped, opts: T::Hash[T.untyped, T.untyped]).void }
      def initialize(response, opts = {})
        super(response, opts)
        @has_next_page = T.let(opts.fetch(:has_next_page, false), T::Boolean)
        @has_previous_page = T.let(opts.fetch(:has_previous_page, false), T::Boolean)
        end_sort = self.results[-1]&.dig("sort")
        @end_cursor = T.let(Search::Responses::PropertyEncoder.encode(end_sort), T.nilable(String))
        start_sort = self.results[0]&.dig("sort")
        @start_cursor = T.let(Search::Responses::PropertyEncoder.encode(start_sort), T.nilable(String))
      end
    end
  end
end
