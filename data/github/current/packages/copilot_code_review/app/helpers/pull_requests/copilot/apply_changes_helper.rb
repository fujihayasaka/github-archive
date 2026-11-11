# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    module ApplyChangesHelper
      # Determines if the Copilot "Apply Changes" button should be rendered for a given comment.
      # This can be used to conditionally show the button that allows Copilot to automatically
      # apply suggested changes from a code review comment.
      #
      # @param comment [PullRequestReview, PullRequestReviewComment] The comment to check
      # @param pull_request [PullRequest] The pull request the comment belongs to
      # @param user [User] The current user viewing the comment
      # @return [Boolean] true if the apply changes button should be rendered
      sig do
        params(
          comment: T.nilable(T.any(PullRequestReview, PullRequestReviewComment)),
          pull_request: T.untyped,
          user: T.untyped,
        ).returns(T::Boolean)
      end
      def self.can_apply_changes?(comment:, pull_request:, user:)
        return false if comment.nil?
        return false unless feature_flag_enabled?(user)
        return false unless pull_request&.repository&.copilot_swe_agent_enabled?(user)
        return false unless pull_request&.head_ref_pushable_by?(user)
        return false if comment_has_suggested_change?(comment, user, pull_request.repository)

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

      sig { params(user: T.untyped, repository: T.nilable(Repository)).returns(T::Boolean) }
      def self.unified_has_suggestion_predicate_enabled?(user:, repository:)
        FeatureFlag.vexi.enabled?(
          :unified_batch_pr_comments,
          [user, repository, repository&.owner].compact,
          default: false
        )
      end

      sig do
        params(
          comment: T.any(PullRequestReview, PullRequestReviewComment),
          user: T.untyped,
          repository: T.nilable(Repository),
        ).returns(T::Boolean)
      end
      def self.comment_has_suggested_change?(comment, user, repository)
        case comment
        when PullRequestReview
          false
        when PullRequestReviewComment
          if unified_has_suggestion_predicate_enabled?(user: user, repository: repository)
            comment.has_suggestion?(require_preload: false)
          else
            comment.body_contains_suggestion?
          end
        else
          T.absurd(comment)
        end
      end

      private_class_method :feature_flag_enabled?, :unified_has_suggestion_predicate_enabled?, :comment_has_suggested_change?

      sig { params(user: T.untyped).returns(T::Boolean) }
      def self.implement_suggestion_refresh?(user:)
        FeatureFlag.vexi.enabled?(:ccr_implement_suggestion_refresh, user, default: false)
      end

      sig { params(user: T.untyped).returns(T::Boolean) }
      def self.model_picker_enabled?(user:)
        FeatureFlag.vexi.enabled?(:copilot_swe_agent_pr_comment_model_picker, user, default: false) &&
          FeatureFlag.vexi.enabled?(:coding_agent_model_selection, user, default: false)
      end

      sig do
        params(
          repository: T.nilable(Repository),
          pull_request: T.untyped,
          user: T.untyped,
          helpers: T.untyped,
        ).returns(T.nilable(String))
      end
      def self.models_url(repository:, pull_request:, user:, helpers:)
        return nil unless repository
        return nil unless helpers.respond_to?(:repo_coding_agent_models_path)
        return nil unless model_picker_enabled?(user: user)

        return nil unless repository.owner

        options = {
          user_id: T.must(repository.owner).display_login,
          repository: repository.name,
        }
        options[:pull_id] = pull_request.id if pull_request
        helpers.repo_coding_agent_models_path(options)
      end
    end
  end
end
