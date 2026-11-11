# typed: strict
# frozen_string_literal: true

module CopilotSpaces
  class RepoScopeFilter
    sig do
      params(
        space: CopilotSpace,
        viewer: User,
      ).returns(T::Boolean)
    end
    def self.authorized?(space:, viewer:)
      new(space: space, viewer: viewer).authorized?
    end

    sig do
      params(
        repository_ids: T::Array[Integer],
        target: T.untyped,
        viewer: User,
      ).returns(T::Boolean)
    end
    def self.authorized_for_repository_ids?(repository_ids:, target:, viewer:)
      return true unless FeatureFlag.vexi.enabled?(:copilot_spaces_granular_repo_scope_check, viewer, default: false)
      return true unless ProgrammaticActor::RepositoryFilter.applicable?(viewer)

      filtered = repository_ids.compact.uniq
      return true if filtered.empty?

      accessible = ProgrammaticActor::RepositoryFilter.perform(
        actor: viewer,
        target: target,
        repository_ids: filtered,
      )
      return true if (filtered - accessible).empty?

      GitHub.dogstats.increment("copilot_spaces.token_auth_denied", tags: [
        "token_type:#{token_type_tag_for(viewer)}",
        "reason:repo_scope_denied",
      ])
      false
    end

    sig { params(viewer: User).returns(String) }
    def self.token_type_tag_for(viewer)
      return "signed_auth_token" if viewer.using_auth_via_signed_auth_token?
      return "classic_pat" if viewer.using_personal_access_token?
      return "fine_grained_pat" if viewer.using_auth_via_user_programmatic_access?
      return "app_user_to_server" if viewer.using_auth_via_integration?
      return "oauth_app" if viewer.using_auth_via_oauth_application?

      "unknown"
    end

    sig do
      params(
        space: CopilotSpace,
        viewer: User,
      ).void
    end
    def initialize(space:, viewer:)
      @space = T.let(space, CopilotSpace)
      @viewer = T.let(viewer, User)
    end

    sig { returns(T::Boolean) }
    def authorized?
      return true unless FeatureFlag.vexi.enabled?(:copilot_spaces_granular_repo_scope_check, viewer, default: false)
      return true unless ProgrammaticActor::RepositoryFilter.applicable?(viewer)

      # denormalized_repository_id was backfilled in github/github#411670.
      repository_ids = space.resources
        .select { |resource| CopilotSpace::REPO_BACKED_RESOURCE_TYPES.include?(resource.resource_type) }
        .map(&:denormalized_repository_id)
        .compact
        .uniq
      return true if repository_ids.empty?

      # Copilot Chat's user-to-server tokens are exempt: the `copilot_chat` app is
      # installed_globally, so RepositoryFilter falls back to the app's global access.
      accessible_repository_ids = ProgrammaticActor::RepositoryFilter.perform(
        actor: viewer,
        target: space.owner,
        repository_ids:,
      )

      denied_repository_ids = repository_ids - accessible_repository_ids
      return true if denied_repository_ids.empty?

      GitHub.dogstats.increment("copilot_spaces.token_auth_denied", tags: [
        "token_type:#{token_type_tag}",
        "reason:#{deny_reason_tag}",
      ])
      false
    end

    private

    sig { returns(CopilotSpace) }
    attr_reader :space

    sig { returns(User) }
    attr_reader :viewer

    sig { returns(String) }
    def token_type_tag
      self.class.token_type_tag_for(viewer)
    end

    sig { returns(String) }
    def deny_reason_tag
      return "target_owner_mismatch" if user_programmatic_access_target_owner_mismatch?

      "repo_scope_denied"
    end

    sig { returns(T::Boolean) }
    def user_programmatic_access_target_owner_mismatch?
      return false unless viewer.using_auth_via_user_programmatic_access?

      grant_target = viewer.programmatic_access&.grant&.target
      grant_target.present? && grant_target != space.owner
    end
  end
end
