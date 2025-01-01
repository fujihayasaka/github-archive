# typed: true
# frozen_string_literal: true

module Platform
  module ConnectionWrappers
    class TimelineItems < ConnectionWrappers::Base
      include IssueTimelineHelper::TotalCountOptimizationHelper

      def total_count
        best_effort_total_count_limit = context.present? ? best_effort_total_count_limit(context[:viewer], arguments) : nil

        if best_effort_total_count_limit.nil?
          timeline.async_total_count
        else
          # If we have a valid best effort total count limit, we use it to get the best effort total count
          page.async_best_effort_total_count(best_effort_total_count_limit)
        end
      end

      def filtered_count
        page.async_filtered_count
      end

      def page_count
        page.async_page_count
      end

      def before_focus_count
        page.async_before_focus_count
      end

      def after_focus_count
        page.async_after_focus_count
      end

      def cursor_for(value)
        page.async_cursor_from_node(value)
      end

      def start_cursor
        page.async_start_cursor
      end

      def end_cursor
        page.async_end_cursor
      end

      def has_next_page
        page.async_has_next_page
      end

      def has_previous_page
        page.async_has_previous_page
      end

      def async_updated_at
        timeline.async_updated_at
      end

      protected

      sig { returns(::Issues::Timeline::Timeline) }
      def timeline
        @items
      end

      sig { returns(::Issues::Timeline::TimelinePage) }
      def page
        @page ||= timeline.get_page(
          before_cursor: before,
          after_cursor: after,
          skip: skip,
          first: first,
          last: last,
          max_page_size: max_page_size,
          focus: focus,
          has_focus: arguments.present? && arguments[:focus_text] && @parent.is_a?(Issue),
          focus_neighbor_count: focus_neighbor_count
        )
      end

      def nodes
        page.async_entries
      end

      def skip
        return @skip if defined?(@skip)
        if arguments.present? && arguments[:skip].present?
          @skip = arguments[:skip] < 0 ? 0 : arguments[:skip]
        end
      end

      def focus
        return arguments[:focus] if arguments.present? && arguments[:focus]

        if arguments.present? && arguments[:focus_text] && @parent.is_a?(Issue) &&
          @after_value.nil? &&
          @before_value.nil? &&
          splitted = arguments[:focus_text].split("-")

          return nil if splitted.length != 2
          name, db_id = splitted

          return nil unless name&.include?("issuecomment") || name&.include?("event")
          return nil unless db_id && Integer(db_id, exception: false)

          focus_event = if name&.include?("issuecomment")
            @parent.comments.find_by(id: db_id.to_i)
          else
            @parent.events.find_by(id: db_id.to_i)
          end
          return nil unless focus_event
          return focus_event.global_relay_id
        end

        nil
      end

      def focus_neighbor_count
        arguments[:focus_neighbor_count] if arguments.present? && arguments[:focus_neighbor_count]
      end
    end
  end
end
