# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    # This mix-in provides common helper methods for [page and page size] <=> [offset and limit] conversions.
    module Offsettable
      extend T::Helpers

      def determine_offset(last, before, after, field)
        if last
          Kernel.raise(Errors::MissingBackwardsPaginationArgument.new(field)) unless before

          offset = CursorGenerator.resolve_cursor(before).to_i
          offset -= last
        elsif after
          offset = CursorGenerator.resolve_cursor(after).to_i
          # We want to see _after_ the cursor, so increment the skip to bypass the specific item at that position.
          offset += 1
        else
          offset = 0
        end

        offset
      end

      # Taken from app/platform/connection_wrappers/commit_history.rb
      # Get the smallest, non-nil number
      def determine_limit(max_page_size, first, last)
        limit = max_page_size
        if first && first < limit
          limit = first
        end
        if last && last < limit
          limit = last
        end
        limit
      end

      def determine_page(limit, offset)
        return 1 if limit.zero? # don't divide by zero

        # We want the 1-based page number, so we need to add 1 to the offset
        # The max will ensure we don't go below 1.
        [(offset / limit).floor + 1, 1].max
      end

      sig { params(offset: Integer).returns(String) }
      def determine_start_cursor(offset)
        CursorGenerator.generate_cursor(offset)
      end

      sig { params(limit: Integer, offset: Integer).returns(String) }
      def determine_end_cursor(limit, offset)
        CursorGenerator.generate_cursor(offset + limit - 1)
      end
    end
  end
end
