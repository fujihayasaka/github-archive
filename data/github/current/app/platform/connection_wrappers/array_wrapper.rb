# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class ArrayWrapper < GraphQL::Pagination::ArrayConnection
      include Platform::ConnectionWrappers::GetLimitedArg
      include Platform::ConnectionWrappers::PaginationValidation

      def initialize(
        relation,
        arguments: {},
        **kwargs
      )
        super(relation, arguments: arguments, **kwargs)
        @max_per_page = calculate_per_page_value(max_page_size.to_i)
        validate_arguments!
      end

      def load_nodes
        @nodes ||= begin
          sliced_nodes = if page = get_limited_arg(:numeric_page)
            per_page = first
            last_page = (items.size / per_page.to_f).ceil

            if page <= last_page
              offset = (per_page * (page - 1))
              items.drop(offset)
            else
              []
            end
          elsif get_limited_arg(:skip)
            offset = get_limited_arg(:skip).to_i
            items.drop(offset)
          elsif before && after
            items[index_from_cursor(after)..index_from_cursor(before) - 1] || []
          elsif before
            items[0..index_from_cursor(before) - 2] || []
          elsif after
            items[index_from_cursor(after)..-1] || []
          else
            items
          end

          @has_previous_page = if last
            # There are items preceding the ones in this result
            sliced_nodes.count > last
          elsif after
            # We've paginated into the Array a bit, there are some behind us
            index_from_cursor(after) > 0
          else
            false
          end

          @has_next_page = if first
            # There are more items after these items
            sliced_nodes.count > first
          elsif before
            # The original array is longer than the `before` index
            index_from_cursor(before) < items.length + 1
          else
            false
          end
          limited_nodes = sliced_nodes
          limited_nodes = limited_nodes.first(first) if first
          limited_nodes = limited_nodes.last(last) if last

          limited_nodes
        end
      end

      def total_count
        items.count
      end
    end
  end
end
