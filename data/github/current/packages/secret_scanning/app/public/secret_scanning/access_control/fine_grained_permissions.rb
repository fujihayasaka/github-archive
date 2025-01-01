# typed: strict
# frozen_string_literal: true

module SecretScanning::AccessControl
  class FineGrainedPermissions
    extend T::Sig

    class PermissionResult < T::Struct
      const :with_permission, T::Set[T.nilable(Integer)]
      const :without_permission, T::Set[T.nilable(Integer)]
    end

    # Returns a struct with two sets
    # - The repository IDs that the actor has the permission for
    # - The repository IDs that the actor does not have the permission for
    sig { params(actor: User, fgp: Symbol, repositories: T::Array[Repository]).returns(PermissionResult) }
    def self.async_batch_check_fgp(actor, fgp, repositories)
      return PermissionResult.new(with_permission: Set.new, without_permission: Set.new) if repositories.empty?

      results = {}
      Promise.all(repositories.map do |repo|
        Platform::Loaders::Permissions::BatchAuthorize.load(actor:, action: fgp, subject: repo).then do |permission|
          results[repo.id] = permission
        end
      end).sync

      can_view = Set.new
      cannot_view = Set.new
      results.each do |repo_id, permission|
        if permission.allow?
          can_view << repo_id
        else
          cannot_view << repo_id
        end
      end

      PermissionResult.new(with_permission: can_view, without_permission: cannot_view)
    end

    # For a Business Owner in an EMU Enterprise or on GHES, we may return alerts from user-owned repos
    # that the Business Owner does not have direct access to but can temporarily unlock.
    # This method returns the repositories that should display an unlock dialog.
    # This method does not check if the user has permission to unlock the repository, it is assumed they can.
    sig { params(current_user: User, repositories: T::Array[Repository]).returns(T::Set[T.nilable(Integer)]) }
    def self.get_unlockable_user_repos(current_user, repositories)
      ghas_for_users = ::AdvancedSecurity::Features::User::AdvancedSecurity.new(current_user)
      return Set.new unless ghas_for_users.feature_available?

      potentially_locked_repos = repositories.filter do |repo|
        next if current_user.id == repo.owner_id

        next unless T.must(repo.owner).user?

        repo
      end

      async_batch_check_fgp(current_user, :view_secret_scanning_alerts, potentially_locked_repos).without_permission
    end
  end
end
