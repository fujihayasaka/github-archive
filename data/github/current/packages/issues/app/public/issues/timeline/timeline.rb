# typed: strict
# frozen_string_literal: true

module Issues
  module Timeline
    class Timeline
      extend T::Sig

      sig { params(issue: Issue, timeline: ::Timeline::BaseTimeline).void }
      def initialize(issue, timeline)
        @issue = issue
        @legacy_timeline = timeline
      end

      sig { returns(::Timeline::BaseTimeline) }
      def legacy_timeline
        @legacy_timeline
      end

      sig { returns(Promise[Integer]) }
      def async_total_count
        @legacy_timeline.async_total_count
      end

      sig { params(before: String, after: String).returns(Promise[Integer]) }
      def async_count_between(before:, after:)
        @legacy_timeline.async_filtered_placeholders.then do |placeholders|
          before_cursor = cursor_key_from_cursor(before)
          after_cursor = cursor_key_from_cursor(after)

          placeholders.count do |placeholder|
            (placeholder.cursor_key <=> before_cursor) > 0 && (placeholder.cursor_key <=> after_cursor) < 0
          end
        end
      end

      sig { params(fallback: T.nilable(Time)).returns(Promise[Time]) }
      def async_updated_at(fallback: nil)
        @legacy_timeline.async_filtered_placeholders.then do |placeholders|
          placeholders.last&.sort_datetimes&.first || fallback || @issue.updated_at
        end
      end

      sig { params(before_cursor: T.nilable(String), after_cursor: T.nilable(String), first: T.nilable(Integer), last: T.nilable(Integer), skip: T.nilable(Integer), max_page_size: T.nilable(Integer), focus: T.nilable(String), has_focus: T.nilable(T::Boolean)).returns(TimelinePage) }
      def get_page(before_cursor: nil, after_cursor: nil, first: nil, last: nil, skip: nil, max_page_size: nil, focus: nil, has_focus: false)
        before = cursor_key_from_cursor(before_cursor)
        after = cursor_key_from_cursor(after_cursor)

        TimelinePage.new(@legacy_timeline, before: before, after: after, skip: skip, first: first, last: last, max_page_size: max_page_size, focus: focus, has_focus: has_focus)
      end

      private

      sig { params(argument: T.nilable(String)).returns(T.nilable([Integer, Integer, String])) }
      def cursor_key_from_cursor(argument)
        return unless argument
        Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(argument)
      end
    end
  end
end
