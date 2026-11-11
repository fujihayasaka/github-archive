# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class PageInfo
      attr_reader :start_cursor, :end_cursor

      def initialize(has_next_page: false, has_previous_page: false, start_cursor: nil, end_cursor: nil, context: nil, connection: nil)
        if connection
          @connection = connection
          # These will be delegated to the `connection`
          # and only fulfilled if needed:
          @has_next_page = nil
          @has_previous_page = nil
        else
          @has_next_page = has_next_page
          @has_previous_page = has_previous_page
        end
        @start_cursor, @end_cursor = start_cursor, end_cursor
      end

      def has_next_page
        @has_next_page.nil? ? @connection.has_next_page : @has_next_page
      end

      def has_previous_page
        @has_previous_page.nil? ? @connection.has_previous_page : @has_previous_page
      end

      alias :has_next_page? :has_next_page
      alias :has_previous_page? :has_previous_page
    end
  end
end
