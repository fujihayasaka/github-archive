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

        if org.business&.erp_feature_enabled?(:enterprise_teams_org_assignment)
          business_team_ids.concat(actor_types_with_ids.fetch(BusinessTeam.user_role_target_type, []))
        end
      end

      # Get the user IDs of the team members
      user_ids.concat(Team.member_ids_of(team_ids, immediate_only: false)) if team_ids.any?
      user_ids.concat(Orgs.domain.teams.user_ids_for_business_teams(business_team_ids)) if business_team_ids.any?

      user_ids.uniq
    end
  end
end
