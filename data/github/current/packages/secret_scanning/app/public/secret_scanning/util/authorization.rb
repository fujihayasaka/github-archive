# typed: strict
# frozen_string_literal: true

module SecretScanning::Util
  class Authorization

    # Separates the default and custom roles from a list of role IDs. Returns [default roles, custom roles]
    sig { params(role_ids: T::Array[Integer]).returns([T::Array[Role], T::Array[Role]]) }
    def self.get_default_and_custom_roles_from_role_ids(role_ids)
      default_roles = []
      custom_roles = []
      role_ids.each do |role_id|
        role = Role.find_by(id: role_id)
        next if role.nil?
        if role.owner_id.nil? && role.owner_type.nil?
          default_roles.push(role)
        else
          custom_roles.push(role)
        end
      end
      [default_roles, custom_roles]
    end

    # Returns the role IDs of the org roles that have the specified FGP
    sig { params(org: Organization, fgp: Symbol).returns(T::Array[Integer]) }
    def self.get_org_role_ids_with_fgp(org, fgp)
      org_role_ids = OrganizationRole.visible_roles(org).map(&:id)
      RolePermission.select(:role_id).where(role_id: org_role_ids, action: fgp).pluck(:role_id)
    end

    # Returns the user IDs of the users who have the specified FGP via custom roles for the org, either directly
    # or via a team assignmemnt.
    sig { params(org: Organization, fgp: Symbol).returns(T::Array[Integer]) }
    def self.get_users_with_fgp_via_custom_roles_for_org(org, fgp)
      org_role_ids_with_fgp = get_org_role_ids_with_fgp(org, fgp)
      _, custom_roles = get_default_and_custom_roles_from_role_ids(org_role_ids_with_fgp)

      user_ids = []
      team_ids = []

      if custom_roles.any?
        # We need to manually specify the target_type, because using `target: org` sets the target_type to "User".
        user_ids.concat(UserRole.where(actor_type: "User", target_id: org.id, target_type: "Organization", role_id: custom_roles).pluck(:actor_id))
        team_ids.concat(UserRole.where(actor_type: "Team", target_id: org.id, target_type: "Organization", role_id: custom_roles).pluck(:actor_id))
      end

      # Get the user IDs of the team members
      user_ids.concat(Team.member_ids_of(team_ids.flatten.uniq, immediate_only: false)) if team_ids.any?

      user_ids.uniq
    end
  end
end
