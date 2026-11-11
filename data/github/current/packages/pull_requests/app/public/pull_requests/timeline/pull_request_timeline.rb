# typed: strict
# frozen_string_literal: true

module PullRequests
  module Timeline
    class PullRequestTimeline < Issues::Timeline::Timeline
      sig { params(pull_request: PullRequest, viewer: T.nilable(User), filter_options: T::Hash[Symbol, T.untyped]).returns(PullRequestTimeline) }
      def self.for(pull_request, viewer, filter_options = {})
        new(pull_request, viewer, filter_options)
      end

      sig { params(pull_request: PullRequest, viewer: T.nilable(User), filter_options: T::Hash[Symbol, T.untyped]).void }
      def initialize(pull_request, viewer, filter_options = {})
        @legacy_timeline = T.let(pull_request.timeline_model_for(viewer, filter_options), ::Timeline::PullRequestTimeline)
        @pull_request = T.let(pull_request, PullRequest)
        @filter_options = T.let(filter_options, T::Hash[Symbol, T.untyped])
        super(T.must(pull_request.issue), @legacy_timeline)
      end

      sig { returns(::Timeline::PullRequestTimeline) }
      def legacy_timeline
        @legacy_timeline
      end

      # Only load a limited set of placeholders. Compute: total_count -
      # items_shown_on_screen, where items_shown_on_screen are the loaded
      # placeholders outside the before..after cursor range (i.e. first
      # page + last page items).
      sig { params(before: String, after: String).returns(Promise[Integer]) }
      def async_count_between(before:, after:)
        before_cursor = cursor_key_from_cursor(before)
        after_cursor = cursor_key_from_cursor(after)

        ::Promise.all([async_total_count, @legacy_timeline.async_filtered_placeholders]).then do |total, placeholders|
          shown_on_screen = placeholders.count do |placeholder|
            !((placeholder.cursor_key <=> before_cursor) > 0 && (placeholder.cursor_key <=> after_cursor) < 0)
          end
          [total - shown_on_screen, 0].max
        end
      end
    end
  end
end
