# typed: true
# frozen_string_literal: true

# Note: In anything user-facing, we decided to refer to this as
# "Base repository permissions" or "Base permissions" if already
# in the context of a repository.
module Configurable
  module DefaultRepositoryPermission
    extend T::Helpers

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    KEY = "default_repository_permission".freeze

    def self.valid_values
      Ability.valid_actions + [:none]
    end

    # Given one of the values from ::valid_values, return the more human
    # readable version for use in copy/messages.
    #
    # value - Symbol or String representing a value from ::valid_values
    #
    # Returns String
    def self.human_friendly_value(value)
      case value.to_s
      when "none"
        "No permission"
      when "read"
        "Read"
      when "write"
        "Write"
      when "admin"
        "Admin"
      when "no_policy"
        "No Policy"
      else
        raise ArgumentError, "Invalid base permission value provided"
      end
    end

    # Thrown when an attempt to update the default repository permission is made
    # while an update is already in progress.
    class AlreadyUpdating < StandardError; end

    # Public: Updates the default repo permissions for an org
    #
    # permission - The permission level to update to. Can be any valid
    #              ability key (:read, etc), or :none.  Also accepts strings.
    # actor - The User performing this action
    #
    # Note: If you want to use this in tests, wrap it in an perform_enqueued_job { } block
    def update_default_repository_permission(permission, force: false, actor:)
      raise ArgumentError unless valid_default_repository_permission?(permission)

      if updating_default_repository_permission?
        raise AlreadyUpdating
      end

      old_permission = default_repository_permission_name
      permission = permission&.to_sym

      # Remove the configuration entry if it's changed to the initial value
      changed = if permission == cleared_repository_permission && !force
        config.delete(KEY, actor)
      else
        config.set!(KEY, permission, actor, force)
      end

      return unless changed
      T.unsafe(self).instrument :update_default_repository_permission,
        actor:          actor,
        old_permission: old_permission,
        permission:     default_repository_permission_name
      sync_default_repository_permission(actor: actor)
    end

    # Public: Clear the default repository permission setting for this model.
    def clear_default_repository_permission(actor:)
      old_permission = default_repository_permission_name
      changed = config.delete(KEY, actor)

      return unless changed
      T.unsafe(self).instrument :clear_default_repository_permission, actor: actor
      sync_default_repository_permission(actor: actor)
    end

    # Public: The default repository permission value
    # Returns an ability action symbol, or :none
    def default_repository_permission
      default_repository_permission_name.to_sym
    end

    # Public: A human-readable version of the organization's default repository
    # permission attribute.
    #
    # Returns a string "read", "write", "admin", "none".
    def default_repository_permission_name
      config.get(KEY) || cleared_repository_permission.to_s
    end

    # Public: Returns whether a default repository permission value is valid
    def valid_default_repository_permission?(permission)
      Configurable::DefaultRepositoryPermission.valid_values.include?(permission&.to_sym)
    end

    # Public: Returns whether a default repository permission policy is set
    def default_repository_permission_policy?
      !!config.final?(KEY)
    end

    # Internal: Queue a job to update default permissions for affected repositories
    def sync_default_repository_permission(actor:)
      return if updating_default_repository_permission?

      SyncOrganizationDefaultRepositoryPermissionJob.enqueue(self, actor: actor)
    end

    # Internal: Sync default repository permission changes to child repositories
    def sync_default_repository_permission!(actor:)
      organizations = if self.is_a?(Organization)
        [self]
      elsif self.is_a?(Business)
        self.organizations
      end

      T.must(organizations).each do |org|
        org_repo_ids = Repositories::Public.active_and_deleted_for_org_ids(org)
        Repository.batched_scope(:id, values: org_repo_ids).each do |repo|
          Ability.throttle do
            if org.default_repository_permission != :none
              # Create/update org -> repo abilities
              repo.add_organization(org, action: org.default_repository_permission)
            else
              # Revoke all org -> repo abilities
              repo.remove_organization(org)
            end
          end

          # clean up users who were granted access to Dependabot alerts, but now do not have acces.
          # this needs to happen when default permission is downgraded below :read
          if org.default_repository_permission == :none
            repo.vulnerability_manager.revoke_users_who_lost_access
          end
        end

        GitHub.logger.info(
          "Finished updating org repo abilities",
          "gh.organization" => org.display_login,
          "code.function" => "sync_default_repository_permission"
        )

        if org.default_repository_permission == :none
          RemoveForksForInaccessibleRepositoriesJob.perform_later(org_repo_ids, org.member_ids)
        end
      end
    end

    def updating_default_repository_permission?
      # Don't block on calling the job in test, as multiple jobs maybe enqueued but not run, as jobs must be explictly performed.
      return false if Rails.env.test?
      return false unless sync_default_repository_permission_job_status.present?
      !sync_default_repository_permission_job_status.finished?
    end

    private

    def sync_default_repository_permission_job_status
      @sync_default_repository_permission_job_status ||= \
        SyncOrganizationDefaultRepositoryPermissionJob.status(self)
    end

    # Repository permission to use if no policy is set
    def cleared_repository_permission
      self.is_a?(Business) ? :no_policy : :read
    end
  end
end
