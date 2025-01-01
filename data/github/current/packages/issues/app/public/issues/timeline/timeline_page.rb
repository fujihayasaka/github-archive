# typed: strict
# frozen_string_literal: true
# rubocop:disable Sorbet/ObsoleteStrictMemoization

module Issues
  module Timeline
    class TimelinePage
      extend T::Sig
      include GitHub::Memoizer

      sig { params(issue_timeline: ::Timeline::BaseTimeline, before: T.nilable([Integer, Integer, String]), after: T.nilable([Integer, Integer, String]), first: T.nilable(Integer), last: T.nilable(Integer), skip: T.nilable(Integer), max_page_size: T.nilable(Integer), focus: T.nilable(String), has_focus: T.nilable(T::Boolean)).void }
      def initialize(issue_timeline, before: nil, after: nil, first: nil, last: nil, skip: nil, max_page_size: nil, focus: nil, has_focus: false)
        @issue_timeline = issue_timeline
        @before = before
        @after = after
        @first = first
        @last = last
        @skip = skip
        @max_page_size = max_page_size
        @focus = focus
        @has_focus = has_focus
      end

      sig { returns(Promise[T::Array[T.untyped]]) }
      memoize def async_entries
        async_paged_placeholders.then do |placeholders|
          Promise.all(
            placeholders.map do |placeholder|
              case placeholder
              when ::Timeline::Placeholder::IssueComment
                Platform::Loaders::ActiveRecord.load(IssueComment, placeholder.id)
              when ::Timeline::Placeholder::IssueEvent
                Platform::Loaders::ActiveRecord.load(IssueEvent, placeholder.id)
              when ::Timeline::Placeholder::CrossReference
                Platform::Loaders::ActiveRecord.load(CrossReference, placeholder.id)
              else
                placeholder
              end
            end
          )
        end
      end

      sig { returns(Promise[Integer]) }
      def async_filtered_count
        async_sliced_placeholders.then(&:size)
      end

      sig { returns(Promise[Integer]) }
      def async_page_count
        async_paged_placeholders.then(&:size)
      end

      sig { returns(Promise[Integer]) }
      def async_before_focus_count
        return Promise.resolve(0) unless @focus

        ::Promise.all([
          async_sliced_placeholders,
          async_paged_placeholders,
        ]).then do |sliced_placeholders, paged_placeholders|
          next 0 unless sliced_placeholders && paged_placeholders
          sliced_placeholders.index(paged_placeholders.first) || 0
        end
      end

      sig { returns(Promise[Integer]) }
      def async_after_focus_count
        return Promise.resolve(0) unless @focus

        ::Promise.all([
          async_sliced_placeholders,
          async_paged_placeholders,
        ]).then do |sliced_placeholders, paged_placeholders|
          next 0 unless sliced_placeholders && paged_placeholders
          index = sliced_placeholders.index(paged_placeholders.last)
          next 0 unless index

          sliced_placeholders.size - index - 1
        end
      end

      sig { returns(Promise[T::Boolean]) }
      def async_has_next_page
        async_sliced_placeholders.then do |sliced_placeholders|
          if @first && !@focus
            sliced_placeholders.count > @first
          else
            async_paged_placeholders.then do |paged_placeholders|
              paged_placeholders.last != sliced_placeholders.last
            end.sync
          end
        end
      end

      sig { returns(Promise[T::Boolean]) }
      def async_has_previous_page
        async_sliced_placeholders.then do |sliced_placeholders|
          if @last && !@focus
            sliced_placeholders.count > @last
          else
            async_paged_placeholders.then do |paged_placeholders|
              paged_placeholders.first != sliced_placeholders.first
            end.sync
          end
        end
      end

      sig { returns(Promise[T.nilable(String)]) }
      def async_start_cursor
        async_entries.then do |entries|
          async_cursor_from_node(entries.first).sync if entries.first
        end
      end

      sig { returns(Promise[T.nilable(String)]) }
      def async_end_cursor
        async_entries.then do |entries|
          async_cursor_from_node(entries.last).sync if entries.last
        end
      end

      sig { params(value: T.untyped).returns(Promise[String]) }
      def async_cursor_from_node(value)
        async_cursor_key_from_entry(value).then do |cursor_key|
          Platform::ConnectionWrappers::CursorGenerator.generate_cursor(cursor_key, version: :v2)
        end
      end

      private

      sig { params(value: T.untyped).returns(Promise[T.nilable([Integer, Integer, String])]) }
      def async_cursor_key_from_entry(value)
        async_value_placeholder_map.then do |map|
          placeholder = map[value]
          placeholder&.cursor_key
        end
      end

      sig { returns(Promise[T::Array[::Timeline::Placeholder::Base]]) }
      def async_paged_placeholders
        @async_paged_placeholders = T.let(nil, T.nilable(Promise[T::Array[::Timeline::Placeholder::Base]]))
        @async_paged_placeholders ||= if @focus
          @issue_timeline.async_filtered_placeholders.then do |placeholders|
            [find_focused_placeholder(placeholders)].compact
          end
        else
          async_sliced_placeholders.then do |placeholders|
            placeholders = placeholders.drop(@skip) if @skip
            placeholders = placeholders.first(@first) if @first
            placeholders = placeholders.last(@last) if @last
            placeholders = placeholders.first(@max_page_size) if @max_page_size && !@first && !@last
            if @has_focus && !@after && !@before
              placeholders = placeholders.clear
            end
            placeholders
          end
        end
      end

      sig { returns(Promise[T::Array[::Timeline::Placeholder::Base]]) }
      def async_sliced_placeholders
        @async_sliced_placeholders = T.let(nil, T.nilable(Promise[T::Array[::Timeline::Placeholder::Base]]))
        @async_sliced_placeholders ||= @issue_timeline.async_filtered_placeholders.then do |placeholders|
          if @before
            placeholders = placeholders.select do |placeholder|
              (placeholder.cursor_key <=> @before) == -1
            end
          end

          if @after
            placeholders = placeholders.select do |placeholder|
              (placeholder.cursor_key <=> @after) == 1
            end
          end

          placeholders
        end
      end

      sig { returns(Promise[T::Hash[T.untyped, ::Timeline::Placeholder::Base]]) }
      memoize def async_value_placeholder_map
        Promise.all([async_entries, async_paged_placeholders]).then do |values, placeholders|
          next {} unless values && placeholders
          values.zip(placeholders).to_h
        end
      end

      sig { params(placeholders: T::Array[::Timeline::Placeholder::Base]).returns(T.nilable(::Timeline::Placeholder::Base)) }
      def find_focused_placeholder(placeholders)
        return unless @focus

        if (focused_placeholder = placeholders.find { |placeholder| placeholder.global_relay_id == @focus })
          focused_placeholder
        else
          # The placeholders implement legacy IDs, but not new-format IDs.
          # We need the real object to get a new format ID, so here we go:
          real_objects = ::Promise.all(placeholders.map(&:async_value)).sync
          focus_idx = real_objects.find_index { |obj| obj.global_relay_id == @focus }
          if focus_idx
            placeholders[focus_idx]
          else
            nil
          end
        end
      end
    end
  end
end
