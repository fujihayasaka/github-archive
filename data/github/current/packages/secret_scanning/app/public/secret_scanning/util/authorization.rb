# typed: strict
# frozen_string_literal: true

module SecretScanning::Util
  class Authorization
    # Returns the user IDs of the users who have the specified FGP via custom roles for the org, either directly
    # or via a team assignmemnt.
    sig { params(org: Organization, fgp: Symbol).returns(T::Array[Integer]) }
    def self.get_users_with_fgp_via_custom_roles_for_org(org, fgp)
      custom_role_ids = Authz.domain.roles.visible_org_role_ids_with_fgp(
        org, fgp, filter: Authz::Domain::Roles::Source::Custom
      )

      user_ids          = T.let([], T::Array[Integer])
      team_ids          = T.let([], T::Array[Integer])
      business_team_ids = T.let([], T::Array[Integer])

      if custom_role_ids.any?
        actor_types_with_ids =
          Authz.domain.user_roles.batch_role_assignments_with_role_ids_for_target(
            target: org,
            role_ids: custom_role_ids,
          )

        user_ids.concat(actor_types_with_ids.fetch(User.user_role_target_type, []))
        team_ids.concat(actor_types_with_ids.fetch(Team.user_role_target_type, []))

        business_team_ids = []

        if org.business.present?
          business_team_ids.concat(actor_types_with_ids.fetch(BusinessTeam.user_role_target_type, []))
        end
      end

      # Get the user IDs of the team members
      user_ids.concat(Team.member_ids_of(team_ids, immediate_only: false)) if team_ids.any?
      user_ids.concat(Orgs.domain.teams.user_ids_for_business_teams(business_team_ids)) if business_team_ids.any?

      user_ids.uniq
    end

    sig { params(user: User, enterprise_role: EnterpriseRole, org: Organization).returns([T::Boolean, String]) }
    def self.user_has_enterprise_role_directly_or_via_team?(user, enterprise_role, org)
      matches = Authz.domain.user_roles.actor_assignments_for_user_and_enterprise_role_on_org(user: user, enterprise_role: enterprise_role, org: org)
      if matches["User"].present?
        return [true, "user has enterprise role: #{enterprise_role.name}"]
      end
      business_team_ids = matches["BusinessTeam"] || []
      role_team_name = BusinessTeam
        .where(id: business_team_ids)
        .limit(1)
        .pluck(:name)
        .first
      return [false, "user does not have enterprise role"] unless role_team_name.present?
      # The Auth domain method already retrieves teams that the user is a part of, so no need to check membership
      # again here.
      [true, "user is member of team (#{role_team_name}) with enterprise role: #{enterprise_role.name}"]
    end

    sig { params(user: User, custom_repo_role: RepositoryRole, repository: Repository).returns([T::Boolean, String]) }
    def self.user_has_custom_role_directly_or_via_team?(user, custom_repo_role, repository)
      matches = Authz.domain.user_roles.actor_assignments_for_user_and_role_on_repository(user: user, repository: repository, repository_role: custom_repo_role)
      if matches["User"].present?
        return true, "user has custom role: #{custom_repo_role.name}" if T.must(matches["User"]).include?(user.id)
      end
      team_actor_ids = []
      team_actor_ids.concat(T.must(matches["BusinessTeam"])) if matches["BusinessTeam"].present?
      team_actor_ids.concat(T.must(matches["Team"])) if matches["Team"].present?

      role_team_name = Team
          .with_business_teams
          .where(id: team_actor_ids)
          .limit(1)
          .pluck(:name)
          .first

      return [false, "user does not have custom role"] unless role_team_name.present?
      [true, "user is member of team (#{role_team_name}) with custom role: #{custom_repo_role.name}"]
    end

    sig { params(business: Business, org: Organization, enterprise_role_ids: T::Array[Integer]).returns([T::Array[User], T::Array[BusinessTeam]]) }
    def self.get_enterprise_role_assignees_visible_to_org(business, org, enterprise_role_ids)
      users = []
      business_teams = []

      # Get all the users and business teams assigned to the specified enterprise roles
      actor_types_to_actor_ids = Authz.domain.user_roles.actors_with_enterprise_roles_for_org(enterprise_role_ids: enterprise_role_ids, org: org)

      # Only keep users who are part of the current org
      user_ids = actor_types_to_actor_ids["User"] || []
      # If user_ids is empty, org.member_ids returns []
      user_ids_for_org = org.member_ids(actor_ids: user_ids)
      users = user_ids_for_org.any? ? User.where(id: user_ids_for_org).to_a : []

      if actor_types_to_actor_ids["BusinessTeam"].present?
        business_team_ids = actor_types_to_actor_ids["BusinessTeam"]
        business_teams = BusinessTeam.where(id: business_team_ids).to_a
      end

      [users, business_teams]
    end
  end
end
