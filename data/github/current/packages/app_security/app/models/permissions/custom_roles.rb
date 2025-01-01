# typed: false
# frozen_string_literal: true

module Permissions
  module CustomRoles
    include Scientist

    extend self

    SUPPORTED_ROLE_TARGET_TYPES = [RepositoryRole, OrganizationRole, EnterpriseRole].freeze

    # Creates a custom role and the corresponding role_permission records.
    #
    # role  - The Custom Role to persist.
    # fgps  - The FGP identifiers.
    #
    # Returns nothing.
    # Raises Role::CustomRoleError if the role or role_permissions cannot be saved.
    def create!(role, fgps: [])
      raise unsupported_type_error(role) unless custom_role_target_valid?(role)

      fgps_to_add = additional_fgps(fgps, role)

      Role.transaction do
        RolePermission.transaction do
          raise Role::CustomRoleError.new("could not create role #{role.name}") unless role.save

          fgps_to_add.each do |fgp|
            role_permission = RolePermission.new(role_id: role.id, action: fgp.action)
            raise Role::CustomRoleError.new("could not create role_permission for role: #{role.name}, fgp: #{fgp.action}") unless role_permission.save
          end

          if role.custom?
            # if a Custom role and all of its associated permissions were created successfully
            # (no Exceptions were raised), record a Hydro event.
            #
            # For the update and delete events, we do Hydro instrumentation at the model level
            # (in role.rb), but for creation, we want to do it here, so the Hydro event doesn't
            # get fired before the associated RolePermission records are created. (if it did,
            # we'd end up recording an event in Hydro without the custom role's FGP's)
            if role.is_a? RepositoryRole
              GlobalInstrumenter.instrument("custom_repository_roles.role_created", {
                role: role,
                org_custom_roles_count: RepositoryRole.custom_roles_for_org(role.owner).count
              })
            elsif role.is_a? OrganizationRole
              GlobalInstrumenter.instrument("custom_organization_roles.role_created", {
                role: role,
                org_custom_org_roles_count: OrganizationRole.custom_roles_for_org(role.owner).count
              })
            elsif role.is_a? EnterpriseRole
              GlobalInstrumenter.instrument("custom_enterprise_roles.role_created", {
                role: role,
                enterprise_custom_roles_count: EnterpriseRole.custom_roles_for_enterprise(role.owner).count
              })
            end
          end
        end
      end
    end

    # Deletes a custom role and assigns its base role to the previously assigned users/teams/repo invitations
    #
    # role    - custom role to delete
    # actor   - user that deleting the custom role
    #
    # Returns nothing
    def destroy!(role, actor = nil)
      return unless role.custom?
      raise unsupported_type_error(role) unless custom_role_target_valid?(role)

      if role.is_a? RepositoryRole
        destroy_repo_role(role, actor)
      elsif role.is_a? OrganizationRole
        destroy_org_role(role, actor)
      elsif role.is_a? EnterpriseRole
        destroy_enterprise_role(role, actor)
      end
    end

    # Updates the abilities records of users/teams assigned to the custom role.
    #
    # role        - the (custom) Role object to update
    # role_params - a Hash of Role attributes to be updated
    # fgps        - an Array of Fine grained permission identifiers to be given to the role
    # actor       - User that is updating the custom role
    #
    # Returns nothing
    # Raises Role::CustomRoleError if the role or role_permissions cannot be updated.
    def update!(role, role_params:, fgps:, actor: nil)
      return unless role.custom?
      raise unsupported_type_error(role) unless custom_role_target_valid?(role)

      if role.is_a? RepositoryRole
        old_role = role.name
        old_base = role.base_role.name
        update_role(role, role_params, fgps)

        unless old_base.eql?(role.base_role.name)
          # udpate underlying ability records
          context = { old_permission: old_role, old_base_role: old_base }
          update_users(role, actor: actor, context: context)
          update_teams(role, actor: actor, context: context)
        end
      elsif role.is_a? OrganizationRole
        update_role(role, role_params, fgps)
      elsif role.is_a? EnterpriseRole
        update_role(role, role_params, fgps)
      end
    end

    # Batch update the abilities records of users assigned to the custom role.
    # Note that org-members can't be assigned an ability below the org default.
    # For those cases we will default to the org default.
    #
    # role    - the (custom) Role object
    # context - Hash of Strings with the users' previous Role {:old_permission, :old_base_role}
    #
    # Returns nothing
    def update_users(role, actor:, context: {})
      raise unsupported_type_error(role) unless role.is_a? RepositoryRole
      org = role.owner
      return unless org.organization?

      if role.greater_or_equal_to_org_default_role?(org)
        update_all_users(role, org, actor: actor, context: context)
      else
        update_members_and_collabs_separately(role, org, actor: actor, context: context)
      end
    end

    private

    def unsupported_type_error(role)
      Role::CustomRoleError.new("roles of type `#{role.class.name}` are not supported")
    end

    def custom_role_target_valid?(role)
      return false unless SUPPORTED_ROLE_TARGET_TYPES.include?(role.class)
      return false if role.is_a?(EnterpriseRole) && !role.owner.feature_enabled?(:custom_enterprise_role_feature)

      true
    end

    def destroy_repo_role(role, actor = nil)
      inherited_base_role = role.base_role.name.to_sym

      user_roles = UserRole.where(actor_type: "User", role_id: role.id)
      unless user_roles.empty?
        org = role.owner
        return unless role.owner.organization?
        BatchUpdateMemberRepoPermissionsJob.batch_enqueue(user_roles: user_roles, action: inherited_base_role, organization: org, role: role, actor: actor)
        GitHub.dogstats.gauge("orgs_roles.delete.count", user_roles.length, tags: ["member_type:member"])
      end

      team_roles = UserRole.where(actor_type: "Team", role_id: role.id)
      unless team_roles.empty?
        Team.batch_enqueue_update_repo_permissions(teams_repos: team_roles, action: inherited_base_role, actor_id: actor&.id, role: role)
        GitHub.dogstats.gauge("orgs_roles.delete.count", team_roles.length, tags: ["member_type:team"])
      end

      repo_invitations = RepositoryInvitation.where(role_id: role.id)
      unless repo_invitations.empty?
        RepositoryInvitation.batch_enqueue_update_repo_permissions(invitations: repo_invitations, setter: actor, action: inherited_base_role, role: role)
        GitHub.dogstats.gauge("orgs_roles.delete.count", repo_invitations.length, tags: ["member_type:invitee"])
      end

      if user_roles.empty? && team_roles.empty? && repo_invitations.empty?
        role.destroy!
      else
        GitHub.dogstats.increment("orgs_roles.delete.queued_to_delete", tags: ["status:queued"])
      end
    end

    def destroy_org_role(role, actor = nil)
      role.destroy!
    end

    def destroy_enterprise_role(role, actor = nil)
      role.destroy!
    end

    # update Role metadata, fgps and base role
    def update_role(role, role_params, fgps)
      raise Role::CustomRoleError.new("updating the target_type of a custom role is not supported") if role_params.key?(:target_type) && role_params[:target_type] != role.target_type

      Role.transaction do
        RolePermission.transaction do
          role.send(:old_role_permissions)  # memoize current FGPs so we can diff later
          role.assign_attributes(role_params) # assign but do not save so that FGP validation runs on updated properties

          prev_fgps = role.custom_role_permissions.map(&:action)
          fgps_to_remove = prev_fgps - fgps
          additional_fgps = fgps - prev_fgps
          fgps_to_add = only_enabled_custom_role_fpgs(additional_fgps, role.owner)

          RolePermission.destroy_by(role: role, action: fgps_to_remove)

          fgps_to_add.each do |fgp|
            role_permission = RolePermission.new(role: role, action: fgp.action)
            raise Role::CustomRoleError.new("could not create role_permission for role: #{role.name}, fgp: #{fgp.action}") unless role_permission.save
          end

          raise Role::CustomRoleError.new("could not update role #{role.name}") unless role.save
        end
      end
    end

    def update_teams(role, actor:, context: {})
      team_roles = UserRole.where(actor_type: "Team", role_id: role.id)

      unless team_roles.empty?
        Team.batch_enqueue_update_repo_permissions(teams_repos: team_roles, action: role.name.to_sym, actor_id: actor&.id, context: context)
        GitHub.dogstats.gauge("orgs_roles.update.count", team_roles.length, tags: ["member_type:team"])
      end
    end

    def update_all_users(role, org, actor:, context: {})
      user_roles = UserRole.where(actor_type: "User", role_id: role.id)
      unless user_roles.empty?
        batch_update_users(user_roles: user_roles, new_role: role.name.to_sym,
                           action: "update", org: org, actor: actor, context: context)
      end
    end

    def update_members_and_collabs_separately(role, org, actor:, context: {})
      user_roles_by_actor = role.user_roles.where(actor_type: "User").index_by(&:actor_id)

      unless user_roles_by_actor.empty?
        actor_ids = user_roles_by_actor.keys
        member_ids = org.member_ids(actor_ids: actor_ids)
        collab_ids = actor_ids - member_ids

        unless member_ids.empty?
          member_user_roles = user_roles_by_actor.values_at(*member_ids).compact
          batch_update_users(user_roles: member_user_roles, new_role: org.default_repository_permission.to_sym,
                             action: "update", org: org, actor: actor, context: context)
        end

        unless collab_ids.empty?
          collab_user_roles = user_roles_by_actor.values_at(*collab_ids).compact
          batch_update_users(user_roles: collab_user_roles, new_role: role.name.to_sym,
                             action: "update", org: org, actor: actor, context: context)
        end
      end
    end

    def batch_update_users(user_roles:, new_role:, action:, org:, role: nil, actor:, context: {})
      BatchUpdateMemberRepoPermissionsJob.batch_enqueue(user_roles: user_roles, action: new_role,
                                             organization: org, role: role, actor: actor, context: context)
      GitHub.dogstats.gauge("orgs_roles.#{action}.count", user_roles.length, tags: ["member_type:member"])
    end

    def batch_update_teams(team_roles:, new_role:, actor:, action:, role: nil)
      Team.batch_enqueue_update_repo_permissions(teams_repos: team_roles, action: new_role, actor_id: actor&.id, role: role)
      GitHub.dogstats.gauge("orgs_roles.#{action}.count", team_roles.length, tags: ["member_type:team"])
    end

    def batch_update_repo_invitations(repo_invitations:, new_role:, actor:, action:, role: nil)
      RepositoryInvitation.batch_enqueue_update_repo_permissions(invitations: repo_invitations, setter: actor, action: new_role, role: role)
      GitHub.dogstats.gauge("orgs_roles.#{action}.count", repo_invitations.length, tags: ["member_type:invitee"])
    end

    # We do not need to add the FGPs inherited by the base role.
    # Return only the additional ones.
    #
    # submitted_fgps - Array of FGP identifiers
    # base_role      - The Role object
    #
    # Returns an Array of Permissions::FineGrainedPermissionIm objects.
    def additional_fgps(submitted_fgps, role)
      if submitted_fgps.nil? || submitted_fgps.empty?
        return []
      end

      if role.is_a? RepositoryRole
        if role.base_role.nil?
          # return submitted FGPs instead?
          return []
        end
        inherited_fgps = role.base_role.permissions.map { |fgp| fgp.action.to_sym }
        only_enabled_custom_role_fpgs(submitted_fgps.map(&:to_sym) - inherited_fgps, role.owner)
      elsif role.is_a?(OrganizationRole) || role.is_a?(EnterpriseRole)
        # same as repo, but can handle missing base role
        # can we convert to just a single implementation and remove all these branches?
        inherited_fgps = role.base_role&.permissions&.map { |fgp| fgp.action.to_sym } || []
        only_enabled_custom_role_fpgs(submitted_fgps.map(&:to_sym) - inherited_fgps, role.owner)
      end
    end

    def only_enabled_custom_role_fpgs(actions, owner)
      # ignore target types in this method - target type matches are be validated by the role permissions model.
      Permissions::FineGrainedPermissionIm.permissions_for_custom_roles(owner, actions: actions)
    end
  end
end
