# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class PullRequestReviewComments < Resolvers::Base
      type "Platform::Connections::PullRequestReviewComment", null: false

      # Some args are added by the field, then used by the connection wrapper
      def resolve(skip_if_collapsed: false, **_args)
        case object
        when ::PullRequestReviewThread
          resolve_pull_request_review_thread_comments(skip_if_collapsed: skip_if_collapsed)
        else
          resolve_comments
        end
      end

      private

      def resolve_comments
        object.async_review_comments_for(context[:viewer]).then do |comments|
          StableArrayWrapper.new(comments)
        end
      end

      def resolve_pull_request_review_thread_comments(skip_if_collapsed:)
        if object.resolved? && skip_if_collapsed
          Promise.resolve(StableArrayWrapper.new([]))
        else
          resolve_comments
        end
      end
    end
  end
end
