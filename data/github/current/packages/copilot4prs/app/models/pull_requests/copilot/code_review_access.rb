# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    # Public: Validates if an actor/user and repo/organization have access to the Copilot code review feature.
    class CodeReviewAccess
      extend T::Sig

      sig { params(actor: T.nilable(User), current_repository: Repository).void }
      def initialize(actor:, current_repository:)
        @repo = current_repository
        @actor = actor
        @repository_owner = T.let(current_repository.owner, T.nilable(User))
      end

      # Public: Returns true if we should trigger automatic reviews for new PRs on this repository.
      sig { returns(T::Boolean) }
      def auto_reviewable?
        return false unless repository_eligible?
        return false if actor_feature_enabled?(:copilot_reviews_automatic_pull_request_review_disabled)
        return false unless repo_or_owner_flag_enabled?(:copilot_reviews_automatic_pull_request_review)
        return false unless repo_or_owner_flag_enabled?(:copilot_pr_reviews_repository_access)
        return false unless actor_feature_enabled?(:copilot_pr_reviews_v0) || actor_feature_enabled?(:copilot_pr_reviews_v1)

        true
      end

      # Public: Validates if the actor can request a review via the "Ask Copilot to review" button.
      sig { returns(T::Boolean) }
      def can_request_via_button?
        return false unless repository_eligible?
        return false unless actor_feature_enabled?(:copilot_pr_reviews_v0)
        return false unless repo_or_owner_flag_enabled?(:copilot_pr_reviews_repository_access)

        true
      end

      # Public: Validates if the actor can create a Copilot review request.
      sig { returns(T::Boolean) }
      def can_create_review_request?
        return false unless repository_eligible?
        return false unless actor_feature_enabled?(:copilot_pr_reviews_v1)
        return false unless repo_or_owner_flag_enabled?(:copilot_pr_reviews_repository_access)

        true
      end

      private

      # Private: Checks if the repository is accessible.
      sig { returns(T::Boolean) }
      def repository_eligible?
        !@repo.public? || Rails.env.development?
      end

      # Private: Checks if a feature is enabled for the actor.
      sig { params(feature: Symbol).returns(T::Boolean) }
      def actor_feature_enabled?(feature)
        return false if @actor.nil?
        @actor.feature_enabled?(feature)
      end

      # Private: Checks if a flag is enabled for the repo or its owner.
      sig { params(flag: Symbol).returns(T::Boolean) }
      def repo_or_owner_flag_enabled?(flag)
        @repo.feature_enabled_for_repo_or_owner?(flag)
      end
    end
  end
end
