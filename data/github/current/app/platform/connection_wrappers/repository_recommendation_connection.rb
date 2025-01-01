# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class RepositoryRecommendationConnection < ConnectionWrappers::Base
      include CursorGenerator

      class Edge
        attr_reader :node, :cursor

        def initialize(node, cursor)
          @node, @cursor = node, cursor
        end
      end

      def self.encode_cursor(offset)
        offset.to_s
      end

      def self.decode_cursor(cursor)
        return 0 unless cursor

        integer_pattern = /\A(\d+)\z/
        if match = cursor.match(integer_pattern)
          # An integer offset
          return match[1].to_i
        end
        raise Errors::Cursor.new(cursor)
      end

      def initialize(
        user,
        first: nil,
        last: nil,
        after: nil,
        before: nil,
        arguments: nil,
        max_page_size: 100,
        **kwargs
      )
        if last
          if before
            skip = self.class.decode_cursor(before)
            skip -= last
          else
            raise Errors::MissingBackwardsPaginationArgument, "before"
          end
        else
          skip = self.class.decode_cursor(after)
          if after
            # We want to see after the cursor, so increment the skip to bypass that recommendation
            skip += 1
          end
        end

        @skip = skip
        @limit = determine_limit(max_page_size, first, last)
        super(
          user,
          first: first,
          last: last,
          after: after,
          before: before,
          arguments: arguments,
          max_page_size: max_page_size,
          **kwargs
        )
      end

      def edges
        @edges ||= results.each_with_index.map do |repo_rec, index|
          Edge.new(repo_rec, self.class.encode_cursor(@skip + index))
        end
      end

      def edge_nodes
        edges.map(&:node)
      end

      def page_info
        return @page_info if defined? @page_info

        start_cursor = nil
        end_cursor = nil

        if unfiltered_results.any?
          start_cursor = self.class.encode_cursor(@skip)
          last_index = unfiltered_results.size - 1
          end_cursor = self.class.encode_cursor(@skip + last_index)
        end

        @page_info = PageInfo.new(
          has_next_page: has_next_page?,
          has_previous_page: @skip > 0,
          start_cursor: start_cursor,
          end_cursor: end_cursor,
        )
      end

      private

      def has_next_page?
        # If the current page has no recommendations, assume there is not another page.
        return false if unfiltered_results.empty?

        unfiltered_next_page_recs = ::RepositoryRecommendation.
          unfiltered_for(@items, page: current_page + 1, per_page: @limit)
        unfiltered_next_page_recs.any?
      end

      def results
        @results ||= results!
      end

      # Private: Determine the page number of the current set of results.
      def current_page
        (@skip / @limit) + 1
      end

      # Private: Returns repository recommendations for the current page. They are not yet filtered
      # for spamminess, dismissals, etc.
      def unfiltered_results
        @unfiltered_results ||= if @items
          ::RepositoryRecommendation.unfiltered_for(@items, page: current_page, per_page: @limit)
        else
          []
        end
      end

      # Private: Returns repository recommendations for the current page. They have been filtered
      # to exclude spammy repositories, dismissed recommendations, etc.
      def results!
        if @items
          RepositoryRecommendation.filter(unfiltered_results, user: @items, mobile_sort_order: @arguments[:mobile_sort_order])
        else
          []
        end
      end

      # Get the smallest non-nil number
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
    end
  end
end
