# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class Timeline < ConnectionWrappers::Base
      def total_count
        @items.async_total_count
      end

      def filtered_count
        async_sliced_placeholders.then(&:size)
      end

      def page_count
        nodes.then(&:size)
      end

      def before_focus_count
        return 0 unless focus

        ::Promise.all([
          async_sliced_placeholders,
          async_paged_placeholders,
        ]).then do |sliced_placeholders, paged_placeholders|
          sliced_placeholders.index(paged_placeholders.first) || 0
        end
      end

      def after_focus_count
        return 0 unless focus

        ::Promise.all([
          async_sliced_placeholders,
          async_paged_placeholders,
        ]).then do |sliced_placeholders, paged_placeholders|
          index = sliced_placeholders.index(paged_placeholders.last)
          next 0 unless index

          sliced_placeholders.size - index - 1
        end
      end

      def cursor_for(value)
        async_value_placeholder_map.then do |map|
          placeholder = map[value]
          cursor_from_placeholder(placeholder)
        end
      end

      def start_cursor
        return @start_cursor if defined?(@start_cursor)
        @start_cursor = async_paged_placeholders.then do |placeholders|
          cursor_from_placeholder(placeholders.first) if placeholders.first
        end
      end

      def end_cursor
        return @end_cursor if defined?(@end_cursor)
        @end_cursor = async_paged_placeholders.then do |placeholders|
          cursor_from_placeholder(placeholders.last) if placeholders.last
        end
      end

      def has_next_page
        async_sliced_placeholders.then do |sliced_placeholders|
          if first && !focus
            sliced_placeholders.count > first
          else
            async_paged_placeholders.then do |paged_placeholders|
              paged_placeholders.last != sliced_placeholders.last
            end
          end
        end
      end

      def has_previous_page
        async_sliced_placeholders.then do |sliced_placeholders|
          if last && !focus
            sliced_placeholders.count > last
          else
            async_paged_placeholders.then do |paged_placeholders|
              paged_placeholders.first != sliced_placeholders.first
            end
          end
        end
      end

      def async_updated_at
        @items.async_filtered_placeholders.then do |placeholders|
          placeholders.last&.sort_datetimes&.first || issue_or_pull_request.updated_at
        end
      end

      private

      def async_value_placeholder_map
        return @async_value_placeholder_map if defined?(@async_value_placeholder_map)
        @async_value_placeholder_map = ::Promise.all([
          nodes,
          async_paged_placeholders,
        ]).then do |values, placeholders|
          values.zip(placeholders).to_h
        end
      end

      def nodes
        return @paged_nodes if defined?(@paged_nodes)

        @paged_nodes = async_paged_placeholders.then do |placeholders|
          ::Promise.all(placeholders.map(&:async_value))
        end
      end

      def async_paged_placeholders
        return @async_paged_placeholders if defined?(@async_paged_placeholders)

        @async_paged_placeholders = if focus
          @items.async_filtered_placeholders.then do |placeholders|
            [find_focused_placeholder(placeholders)].compact
          end
        else
          async_sliced_placeholders.then do |placeholders|
            placeholders = placeholders.drop(skip) if skip
            placeholders = placeholders.first(first) if first
            placeholders = placeholders.last(last) if last
            placeholders = placeholders.first(max_page_size) if max_page_size && !first && !last
            placeholders
          end
        end
      end

      def async_sliced_placeholders
        return @async_sliced_placeholders if defined?(@async_sliced_placeholders)
        @async_sliced_placeholders = @items.async_filtered_placeholders.then do |placeholders|
          if before_cursor
            placeholders = placeholders.select do |placeholder|
              (placeholder.cursor_key <=> before_cursor) == -1
            end
          end

          if after_cursor
            placeholders = placeholders.select do |placeholder|
              (placeholder.cursor_key <=> after_cursor) == 1
            end
          end

          placeholders
        end
      end

      def skip
        return @skip if defined?(@skip)
        if arguments.present? && arguments[:skip].present?
          @skip = arguments[:skip] < 0 ? 0 : arguments[:skip]
        end
      end

      def focus
        return @focus if defined?(@focus)
        if arguments.present? && arguments[:focus].present?
          @focus = arguments[:focus]
        end
      end

      def find_focused_placeholder(placeholders)
        return unless focus

        if (focused_placeholder = placeholders.find { |placeholder| placeholder.global_relay_id == focus })
          focused_placeholder
        else
          # The placeholders implement legacy IDs, but not new-format IDs.
          # We need the real object to get a new format ID, so here we go:
          real_objects = ::Promise.all(placeholders.map(&:async_value)).sync
          focus_idx = real_objects.find_index { |obj| obj.global_relay_id == focus }
          if focus_idx
            placeholders[focus_idx]
          else
            nil
          end
        end
      end

      def before_cursor
        return @before_cursor if defined?(@before_cursor)
        @before_cursor = cursor_for_arg(before)
      end

      def after_cursor
        return @after_cursor if defined?(@after_cursor)
        @after_cursor = cursor_for_arg(after)
      end

      def cursor_for_arg(argument)
        return unless argument
        CursorGenerator.resolve_cursor(argument)
      end

      def cursor_from_placeholder(placeholder)
        CursorGenerator.generate_cursor(placeholder.cursor_key, version: :v2)
      end

      def issue_or_pull_request
        parent
      end
    end
  end
end
