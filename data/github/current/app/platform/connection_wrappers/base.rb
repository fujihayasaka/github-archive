# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class Base < GraphQL::Pagination::Connection
      include Platform::ConnectionWrappers::PaginationValidation

      def initialize(*args, **kwargs)
        super
        @max_per_page = calculate_per_page_value(max_page_size.to_i)
        validate_arguments!
      end
    end
  end
end
