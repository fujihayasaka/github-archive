# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class ResultErrorWrapper < GraphQL::Pagination::Connection

      def throw_error
        case items
        when GH::Result::Error::ServiceUnavailable then raise Errors::ServiceUnavailable.new(items.message)
        else
          raise Errors::Internal
        end
      end

      alias :nodes :throw_error
      alias :cursor_for :throw_error

      def has_next_page? = false
      def has_previous_page? = false
      def total_count = 0
    end
  end
end
