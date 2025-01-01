# typed: strict
# frozen_string_literal: true

module PullRequests
  module Timeline
    class PullRequestTimeline < Issues::Timeline::Timeline
      extend T::Sig

      sig { params(pull_request: PullRequest, viewer: T.nilable(User), filter_options: T::Hash[Symbol, T.untyped]).returns(PullRequestTimeline) }
      def self.for(pull_request, viewer, filter_options = {})
        new(pull_request, viewer, filter_options)
      end

      sig { params(pull_request: PullRequest, viewer: T.nilable(User), filter_options: T::Hash[Symbol, T.untyped]).void }
      def initialize(pull_request, viewer, filter_options = {})
        @legacy_timeline = T.let(pull_request.timeline_model_for(viewer, filter_options), ::Timeline::PullRequestTimeline)
        super(T.must(pull_request.issue), @legacy_timeline)
      end

      sig { returns(::Timeline::PullRequestTimeline) }
      def legacy_timeline
        @legacy_timeline
      end
    end
  end
end
