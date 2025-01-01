# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class DriftwoodQuery < ConnectionWrappers::Base
      include CursorGenerator

      def initialize(*args, **kwargs)
        super
        protect_against_duplicate_cursor_parameters!
      end

      def cursor_for(item)
        encode_cursor(item[:@timestamp])
      end

      def page_info
        @page_info ||= begin
          synced_nodes = edge_nodes.sync
          PageInfo.new(
            connection: self,
            start_cursor: results.before_cursor,
            end_cursor: results.after_cursor,
          )
        end
      end

      def has_next_page
        @items.has_next_page?
      end

      def has_previous_page
        @items.has_previous_page?
      end

      def total_count
        @total_count ||= results.total_count
      end

      def edge_nodes
        @edge_nodes ||= ::Promise.resolve(normalize(results.results))
      end

      def end_cursor
        page_info.end_cursor
      end

      def start_cursor
        page_info.start_cursor
      end

      def results
        @results ||=
          begin
            edges_limit = (first || last)
            @items.per_page = edges_limit
            @items.after = after || ""
            @items.before = before_cursor || ""
            @items.execute
          end
      rescue Driftwood::TwirpUtil::RateLimitedError
        raise Errors::RateLimited.new("You can't perform that action at this time. Please try again later.")
      end

      private

      def encode_cursor(cursor)
        Base64.urlsafe_encode64(cursor.to_s) if cursor
      end

      def before_cursor
        if before
          before
        elsif last
          # If the user is trying to search backwards, without a before cursor, just use 0
          # Since all of the dates will be after that
          # This way we don't need to implement complicated logic to find the end of the list
          "0"
        end
      end

      def normalize(entries)
        entries.map! do |hit|
          hit = ::Audit::Elastic::Hit.new(hit)
          hit.after_initialize
          hit
        end
      end

      def protect_against_duplicate_cursor_parameters!
        # We need to build out support for before and after. Until then, let's
        # raise an exception.
        if before.present? && after.present?
          raise Errors::DuplicateBeforeAfterPaginationBoundaries.new
        end
      end
    end
  end
end
