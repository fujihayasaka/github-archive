# typed: strict
# frozen_string_literal: true

module Issues
  module Timeline
    class IssueTimeline < Timeline
      sig { params(issue: Issue, viewer: T.nilable(User), filter_options: T::Hash[Symbol, T.untyped]).returns(IssueTimeline) }
      def self.for(issue, viewer, filter_options = {})
        new(issue, viewer, filter_options)
      end

      sig { params(issue: Issue, viewer: T.nilable(User), filter_options: T::Hash[Symbol, T.untyped]).void }
      def initialize(issue, viewer, filter_options = {})
        @legacy_timeline = T.let(issue.timeline_model_for(viewer, filter_options), ::Timeline::IssueTimeline)
        super(issue, @legacy_timeline)
      end

      sig { returns(::Timeline::IssueTimeline) }
      def legacy_timeline
        @legacy_timeline
      end
    end
  end
end
