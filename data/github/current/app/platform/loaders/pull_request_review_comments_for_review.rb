# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PullRequestReviewCommentsForReview < Platform::Loader
      def self.load(pull_request_review_id, viewer)
        self.for(viewer).load(pull_request_review_id)
      end

      def initialize(viewer)
        @viewer = viewer
      end

      private

      attr_reader :viewer

      def fetch(pull_request_review_ids)
        scope = ::PullRequestReviewComment.
          eager_load(:pull_request_review_thread).
          where(pull_request_review_id: pull_request_review_ids).
          visible_to(viewer)

        scope.group_by(&:pull_request_review_id).tap do |results|
          results.default_proc = -> (_, _) { [] }
        end
      end
    end
  end
end
