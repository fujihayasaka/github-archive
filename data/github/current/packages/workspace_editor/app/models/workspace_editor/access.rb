# typed: strict
# frozen_string_literal: true

module WorkspaceEditor
  class Access
    # Public: Validates if an actor/user and repo/organization have access to the Copilot code review feature.
    include GitHub::Memoizer

    sig { params(actor: T.nilable(T.any(::User, ::Organization, ::Business)), current_repository: T.nilable(Repository), pull_request: T.nilable(PullRequest)).void }
    def initialize(actor:, current_repository:, pull_request: nil)
      @actor = actor
      @repo = current_repository
    end


    # Public: Validates if the actor can create a Copilot review request.
    # Can also be used to answer other feature-visibility questions, like repo rule settings.
    sig { returns(T::Boolean) }
    def has_workspace_editor_preview_access?
      log("checking if actor can create review request")

      return false unless actor_eligible?
      return false unless repository_eligible?
      return false unless has_quota_remaining?

      log("actor can create review request")
      true
    end


    # Public: Validates if the actor has quota remaining to create a Copilot review request.
    sig { returns(T::Boolean) }
    def has_quota_remaining?
      log("checking if actor has quota remaining to create review request")
      return false unless code_review_quota.has_quota_remaining?
      log("actor has quota remaining to create review request")
      true
    end

    private

    sig { returns(PullRequests::Copilot::CodeReviewQuota) }
    memoize def code_review_quota
      PullRequests::Copilot::CodeReviewQuota.new(copilot_user: copilot_user)
    end

    sig { params(message: String).void }
    def log(message)
      GitHub.logger.info("workspace_editor_access: #{message}",
        "gh.repository.id" => @repo&.name,
        "gh.user.id" => @actor&.id,
        "gh.user.login" => @actor&.display_login,
      )
    end

    sig { returns(T::Boolean) }
    def actor_eligible?
      return false unless @actor.is_a?(::User)
      log("checking if actor is eligible")

      return true if actor_feature_enabled?(:copilot_code_review_v1)
      log("actor is not in copilot_code_review_v1")

      return false unless actor_feature_enabled?(:workspace_editor_preview)
      log("actor is in workspace_editor_preview")

      # User is in the public preview, so we also require:
      # - Any Copilot license
      # - Beta features opted in
      return false unless copilot_user&.has_copilot_access?
      log("user actor has copilot access")
      return false unless copilot_user&.beta_features_github_chat_enabled?
      log("user actor has beta features enabled")

      true
    end

    # Private: Checks if the repository is accessible.
    sig { returns(T::Boolean) }
    def repository_eligible?
      true
    end

    # Private: Checks if a feature is enabled for the actor.
    sig { params(feature: Symbol).returns(T::Boolean) }
    def actor_feature_enabled?(feature)
      return false if @actor.nil?
      @actor.feature_enabled?(feature)
    end

    sig { returns(T.nilable(::Copilot::Public::User)) }
    memoize def copilot_user
      return nil unless @actor.is_a?(::User)
      ::Copilot::Public::User.new(@actor)
    end
  end
end
