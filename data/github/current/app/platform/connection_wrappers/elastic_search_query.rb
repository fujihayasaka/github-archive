# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class ElasticSearchQuery < ConnectionWrappers::Base

      include CursorGenerator

      def cursor_for(item)
        offset = starting_offset + edge_nodes.sync.index(item) + 1
        CursorGenerator.generate_cursor(offset)
      end

      def page_info
        @page_info ||= begin
          synced_nodes = edge_nodes.sync
          PageInfo.new(
            has_next_page: total_count > starting_offset + limit.to_i,
            has_previous_page: starting_offset > 0,
            start_cursor: synced_nodes.first ? cursor_for(synced_nodes.first) : nil,
            end_cursor: synced_nodes.last ? cursor_for(synced_nodes.last) : nil,
          )
        end
      end

      def query
        @items.query
      end

      def total_count
        @total_count ||= query.count
      end

      def open_count
        state_counts["open"] || 0
      end

      def closed_count
        state_counts["closed"] || 0
      end

      def state_counts
        @state_counts ||= @items.counts_query.execute.state_counts
      end

      def results
        @results ||= begin
          query.per_page = limit
          query.configure_page_and_offset(offset: starting_offset)
          query.execute
        end
      end

      def edge_nodes
        @edge_nodes ||= begin
          query_results = self.results.results
          @ids = query_results.map { |result| result["_id"] }
          if @items.respond_to?(:model_to_be_queried)
            # Use a loader to batch the query in order to avoid refetching any records.
            ::Promise.all(@ids.map { |id| Loaders::ActiveRecord.load(@items.model_to_be_queried, id.to_i) })
          else
            ::Promise.resolve(query_results)
          end
        end
      end

      def limit
        @limit ||= if first
          first
        else
          if previous_offset < 0
            previous_offset + last.to_i
          else
            last
          end
        end
      end

      def offset_from_cursor(cursor)
        return unless cursor
        CursorGenerator.resolve_cursor(cursor).to_i
      end

      def starting_offset
        @initial_offset ||= begin
          if before
            [previous_offset, 0].max
          else
            previous_offset
          end
        end
      end

      # Offset from the previous selection, if there was one
      # Otherwise, zero
      def previous_offset
        @previous_offset ||= if after
          offset_from_cursor(after)
        elsif before
          offset_from_cursor(before) - last.to_i - 1
        elsif last
          total_count - last.to_i
        else
          0
        end
      end
    end
  end
end
