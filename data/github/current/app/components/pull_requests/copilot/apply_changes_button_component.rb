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
        return false unless feature_flag_enabled?
        return false unless repository&.copilot_swe_agent_enabled?(current_user)
        return false unless @pull_request.head_ref_pushable_by?(current_user)
        return false if has_suggested_change?

        if @comment.is_a?(PullRequestReview)
          return false unless @comment.copilot?
          return false unless @comment.review_threads.present?
        end

        true
      end

      sig { returns(T::Boolean) }
      def has_suggested_change?
        # Check if this specific comment has a code suggestion
        return false unless @comment.respond_to?(:body_contains_suggestion?)

        @comment.body_contains_suggestion?
      end

      sig { returns(T.nilable(Repository)) }
      def repository
        @pull_request&.repository
      end

      sig { returns(T::Boolean) }
      def feature_flag_enabled?
        FeatureFlag.vexi.enabled?(:copilot_code_review_reply_hint, current_user, default: false)
      end
    end
  end
end
