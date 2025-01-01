# typed: strict
# frozen_string_literal: true

module Platform
  module Helpers
    # The single purpose of this wrapper is to distinguish resolved timelines between `timeline` and `timelineItems`
    # so we can register a separate connection wrapper for each.
    class TimelineWrapper
      sig { params(timeline: ::Issues::Timeline::Timeline).void }
      def initialize(timeline)
        @timeline = timeline
      end

      sig { returns(::Issues::Timeline::Timeline) }
      def timeline
        @timeline
      end
    end
  end
end
