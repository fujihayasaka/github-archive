# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class StableArray < ConnectionWrappers::Base
      include Platform::ConnectionWrappers::GetLimitedArg

      def cursor_for(item)
        CursorGenerator.generate_cursor(data_from_node(item), version: :v2)
      end

      def page_count
        nodes.size
      end

      def filtered_count
        sliced_nodes.size
      end

      def before_focus_count
        return 0 unless @arguments[:focus]

        sliced_nodes.index(nodes.first) || 0
      end

      def after_focus_count
        return 0 unless @arguments[:focus]

        index = sliced_nodes.index(nodes.first)
        return 0 unless index

        sliced_nodes.size - index - 1
      end

      def has_previous_page
        return false unless sorted_nodes.any?

        if capped_last
          sliced_nodes.count > capped_last
        elsif after
          after_cursor_data = data_from_cursor(after)

          result = after_cursor_data <=> node_to_cursor_data[sorted_nodes.first]
          !result.nil? && result >= 0
        else
          skipped = skip || 0
          !skipped.zero?
        end
      end

      def has_next_page
        return false unless sorted_nodes.any?

        skipped = skip || 0
        if capped_first
          sliced_nodes.count - skipped > capped_first
        elsif max_page_size
          sliced_nodes.count - skipped > max_page_size
        elsif before
          before_cursor_data = data_from_cursor(before)

          result = before_cursor_data <=> node_to_cursor_data[sorted_nodes.last]
          !result.nil? && result <= 0
        else
          false
        end
      end

      def total_count
        @items.count
      end

      # apply first / last limit results
      def nodes
        @paged_nodes ||= begin
          items = sliced_nodes

          if @arguments[:focus]
            items = [find_focused_node(items)]
          else
            items = items.drop(skip) if skip
            items = items.first(first) if first
            items = items.last(last) if last
            items = items.first(max_page_size) if max_page_size && !first && !last
          end

          items
        end
      end

      private

      def data_from_node(item)
        @items.sort_by_proc.call(item).map do |value|
          case value
          when Time
            value.utc.iso8601
          else
            value
          end
        end
      end

      def data_from_cursor(cursor)
        decoded = CursorGenerator.safe_urlsafe_decode64(cursor)

        if decoded.starts_with?(CursorGenerator::CURSOR_IDENTIFIER)
          CursorGenerator.resolve_cursor(cursor)
        else
          # We want to keep compatibility with cursor generated from `ArrayConnection`
          @items[decoded.to_i] && data_from_node(@items[decoded.to_i])
        end
      end

      def capped_first
        return @capped_first if defined? @capped_first

        @capped_first = get_limited_arg(:first)
        @capped_first = max_page_size if @capped_first && max_page_size && @capped_first > max_page_size
        @capped_first
      end

      def skip
        return @skip if defined? @skip

        @skip = get_limited_arg(:skip)
      end

      def capped_last
        return @capped_last if defined? @capped_last

        @capped_last = get_limited_arg(:last)
        @capped_last = max_page_size if @capped_last && max_page_size && @capped_last > max_page_size
        @capped_last
      end

      def find_focused_node(items)
        return unless @arguments[:focus]

        items.find { |item| item.global_relay_id == @arguments[:focus] }
      end

      # Apply cursors to edges
      def sliced_nodes
        return @sliced_nodes if defined?(@sliced_nodes)

        @sliced_nodes = sorted_nodes

        if page = get_limited_arg(:numeric_page)
          return @sliced_nodes if page == 1

          per_page = first
          last_page = (@items.size / per_page.to_f).ceil

          if page <= last_page
            offset = (per_page * (page - 1))
            @sliced_nodes = @sliced_nodes.drop(offset)
          else
            @sliced_nodes = []
          end
        elsif after || before
          if after
            if after_cursor_data = data_from_cursor(after)
              @sliced_nodes = @sliced_nodes.drop_while do |node|
                result = (node_to_cursor_data[node] <=> after_cursor_data)
                result && result <= 0
              end
            else
              @sliced_nodes = []
            end
          end

          if before && (before_cursor_data = data_from_cursor(before))
            @sliced_nodes = @sliced_nodes.take_while do |node|
              result = (node_to_cursor_data[node] <=> before_cursor_data)
              result.nil? || result < 0
            end
          end
        end

        @sliced_nodes
      end

      def sorted_nodes
        return @sorted_nodes if defined?(@sorted_nodes)

        @sorted_nodes = @items.sort_by { |node| node_to_cursor_data[node] }
      end

      def node_to_cursor_data
        return @node_to_cursor_data if defined?(@node_to_cursor_data)

        @node_to_cursor_data = Hash[@items.map { |node| [node, data_from_node(node)] }]
      end
    end
  end
end
