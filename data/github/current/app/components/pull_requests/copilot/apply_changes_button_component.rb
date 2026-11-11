# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    class ApplyChangesButtonComponent < ApplicationComponent
      sig do
        params(
          comment: T.untyped,
          pull_request: T.untyped,
          comment_permalink: T.nilable(String),
          is_overview_comment: T::Boolean
        ).void
      end
      def initialize(comment:, pull_request:, comment_permalink:, is_overview_comment:)
        @comment = comment
        @pull_request = pull_request
        @comment_permalink = comment_permalink
        @is_overview_comment = is_overview_comment
      end

      private

      sig { returns(T::Boolean) }
      def render?
        PullRequests::Copilot::ApplyChangesHelper.can_apply_changes?(
          comment: @comment,
          pull_request: @pull_request,
          user: current_user,
        )
      end

      sig { returns(T.nilable(Repository)) }
      def repository
        @pull_request&.repository
      end

      sig { returns(Integer) }
      def comment_count
        if @comment.is_a?(PullRequestReview)
          @comment.review_threads.size
        else
          0
        end
      end
    end
  end
end
