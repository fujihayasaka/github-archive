# typed: strict
# frozen_string_literal: true

module Platform
  module Helpers
    class QueryLimiter
      include ActionView::Helpers::NumberHelper

      sig { params(query: String).void }
      def initialize(query)
        @query = query

        @query_byte_size = T.let(query.bytesize, Integer)
        @max_byte_size = T.let(Platform::MAX_BYTE_SIZE, Integer)

        @query_directive_count = T.let(query.count("@"), Integer)
        @max_directive_count = T.let(Platform::MAX_DIRECTIVE_COUNT, Integer)
      end

      sig { returns(T::Boolean) }
      def exceeded?
        query? && exceeds_max_byte_size? && exceeds_max_directive_count?
      end

      sig { returns(String) }
      def error_message
        formatted_actual_byte_size = number_with_delimiter(@query_byte_size)
        formatted_max_byte_size = number_with_delimiter(@max_byte_size)

        formatted_actual_directive_count = number_with_delimiter(@query_directive_count)
        formatted_max_directive_count = number_with_delimiter(@max_directive_count)

        "Your payload is #{formatted_actual_byte_size} bytes and contains #{formatted_actual_directive_count} directives, " \
        "which exceeds the maximum limit of #{formatted_max_byte_size} bytes and #{formatted_max_directive_count} directives."
      end

      private

      sig { returns(T::Boolean) }
      def query?
        @query.start_with?("query")
      end

      sig { returns(T::Boolean) }
      def exceeds_max_byte_size?
        @query_byte_size > @max_byte_size
      end

      sig { returns(T::Boolean) }
      def exceeds_max_directive_count?
        @query_directive_count > @max_directive_count
      end
    end
  end
end
