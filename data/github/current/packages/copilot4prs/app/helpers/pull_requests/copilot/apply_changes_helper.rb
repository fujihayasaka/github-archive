# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    module ApplyChangesHelper

      # Determines if the Copilot "Apply Changes" button should be rendered for a given comment.
      # This can be used to conditionally show the button that allows Copilot to automatically
      # apply suggested changes from a code review comment.
      #
      # @param comment [PullRequestReview, PullRequestReviewComment, #body_contains_suggestion?] The comment to check
      # @param pull_request [PullRequest] The pull request the comment belongs to
      # @param user [User] The current user viewing the comment
      # @return [Boolean] true if the apply changes button should be rendered
      sig do
        params(
          comment: T.untyped,
          pull_request: T.untyped,
          user: T.untyped,
        ).returns(T::Boolean)
      end
      def self.can_apply_changes?(comment:, pull_request:, user:)
        return false if comment.nil?
        return false unless feature_flag_enabled?(user)
        return false unless pull_request&.repository&.copilot_swe_agent_enabled?(user)
        return false unless pull_request&.head_ref_pushable_by?(user)
        return false if comment_has_suggested_change?(comment)

        if comment.is_a?(PullRequestReview)
          # Should also support the new shared component with the automated variant type
          return false unless comment.copilot? || comment.automated?
          return false unless comment.review_threads.present?
        end

        true
      end

      sig { params(user: T.untyped).returns(T::Boolean) }
      def self.feature_flag_enabled?(user)
        FeatureFlag.vexi.enabled?(:copilot_code_review_reply_hint, user, default: false)
      end

      sig { params(comment: T.untyped).returns(T::Boolean) }
      def self.comment_has_suggested_change?(comment)
        return false unless comment.respond_to?(:body_contains_suggestion?)

        comment.body_contains_suggestion?
      end

      private_class_method :feature_flag_enabled?, :comment_has_suggested_change?
    end
  end
end
