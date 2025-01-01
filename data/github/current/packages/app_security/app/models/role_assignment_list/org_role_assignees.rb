# typed: strict
# frozen_string_literal: true

module RoleAssignmentList
  class OrgRoleAssignees
    include GitHub::Memoizer

    class ActorType < T::Enum
      enums do
        User = new("User")
        Team = new("Team")
      end
    end

    sig do
      params(
        organization: Organization,
        direct_only: T::Boolean,
        role_ids: T::Array[T.nilable(Integer)],
      ).void
    end
    def initialize(organization:, direct_only: true, role_ids: [])
      @organization = organization
      @direct_only = direct_only
      @role_ids = T.let(role_ids.compact, T::Array[Integer])
    end

    sig { params(actor_type: String).returns(T::Array[Integer]) }
    def ids(actor_type)
      case ActorType.deserialize(actor_type)
      when ActorType::User
        user_assignee_ids
      when ActorType::Team
        team_assignee_ids
      end
    end

    sig { params(assignees: T.any(T::Array[User], T::Array[Team])).returns(OrgRoleAssignments) }
    def assignments_for(assignees:)
      case assignees.first
      when User
        role_assignments = OrgRoleAssignments.new(
          organization: @organization,
          actor_type: "User",
          direct_only: @direct_only,
          role_ids: @role_ids,
          fetch_user_assignments: false,
          fetch_team_assignments: false,
        )

        role_assignments.assignments = fetch_assignments_for_user_assignees(T.cast(assignees, T::Array[User]))

        role_assignments
      when Team
        # TODO: This is not ideal as we're loading all of the teams and then filtering
        # out the data we don't care about.
        OrgRoleAssignments.new(
          organization: @organization,
          actor_type: "Team",
          direct_only: @direct_only,
          role_ids: @role_ids,
          fetch_user_assignments: false,
        )
      else
        # Do not load any data if there aren't any assignees.
        role_assignments = OrgRoleAssignments.new(
          organization: @organization,
          actor_type: "User",
          direct_only: @direct_only,
          role_ids: @role_ids,
          fetch_user_assignments: false,
          fetch_team_assignments: false,
        )

        role_assignments.assignments = []

        role_assignments
      end
    end

    sig { returns(T::Array[Integer]) }
    memoize def team_assignee_ids
      return team_ids_granted_direct_user_roles if direct_only?
      (team_ids_granted_direct_user_roles + descendant_team_ids_of_granted_teams).uniq
    end

    sig { returns(T::Array[Integer]) }
    memoize def user_assignee_ids
      return user_ids_granted_direct_user_roles if direct_only?
      (user_ids_granted_direct_user_roles + team_member_ids_of_granted_teams_and_descendants).uniq
    end

    private

    sig { returns(T::Array[Integer]) }
    memoize def descendant_team_ids_of_granted_teams
      return [] if team_actor_user_roles.none?

      teams = Team.batched_scope(:id, values: team_ids_granted_direct_user_roles).to_a
      Team.descendant_ids(teams, immediate_only: false)
    end

    sig { returns(T::Boolean) }
    def direct_only?
      @direct_only
    end

    sig { params(assignees: T::Array[User]).returns(T::Array[RoleAssignment]) }
    def fetch_assignments_for_user_assignees(assignees)
      return [] if user_roles_query.none?

      assignees_cache = T.let(assignees.index_by(&:id), T::Hash[Integer, User])
      assignments     = []

      user_actor_user_roles.where(actor_id: assignees_cache.keys).each do |user_role|
        assignments << RoleAssignment.new(actor: T.must(assignees_cache[user_role.actor_id]), role: user_role.role)
      end

      return assignments if direct_only?
      return assignments if team_actor_user_roles.none?

      assignments + fetch_assignments_for_user_assignees_through_teams(assignees_cache)
    end

    sig { params(assignees_cache: T::Hash[Integer, User]).returns(T::Array[RoleAssignment]) }
    def fetch_assignments_for_user_assignees_through_teams(assignees_cache)
      # Fetch all indirect user memberships in teams that are assigned to roles
      # parent in this context reflects the team the user is a direct member of, which indirectly grants
      # membership to the team that is actually assigned the role
      team_memberships_scope = Ability.where(
        subject_type: "Team",
        subject_id: team_ids_granted_direct_user_roles,
        actor_type: "User",
        actor_id: assignees_cache.keys,
      )

      return [] if team_memberships_scope.none?
      team_memberships = team_memberships_scope.eager_load(:parent).to_a

      # collect the direct and indirect memberships in teams that are assigned to roles by assigned team id
      membership_by_parent = team_memberships.group_by(&:subject_id)

      indirect_user_ids = T.let([], T::Array[Integer])

      team_ids = team_ids_granted_direct_user_roles
      team_memberships.each do |ability|
        indirect_user_ids << ability.actor_id
        team_ids << T.must(ability.parent).subject_id if ability.priority == "indirect"
      end

      teams_cache = T.let(Team.batched_scope(:id, values: team_ids).to_a.index_by(&:id), T::Hash[Integer, Team])

      assignments = T.let([], T::Array[RoleAssignment])

      team_actor_user_roles.each do |taur|
        # for every team that is assigned, find the users who are directly and indirectly members of those teams
        assigned_team = teams_cache[taur.actor_id]
        next unless assigned_team

        user_memberships = membership_by_parent.fetch(assigned_team.id, [])
        next if user_memberships.empty?

        # if the user is a member of a child team of the assigned team, the ability record will have an indirect priority
        # and have a parent_id linking to the direct membership
        user_memberships.each do |m|
          member_of = m.priority == "direct" ? assigned_team : teams_cache[(T.must(m.parent).subject_id)]
          user = assignees_cache[m.actor_id]
          assignments << RoleAssignment.new(actor: T.must(user), role: taur.role, assigned_team: assigned_team, through: member_of)
        end
      end

      assignments
    end

    sig { returns(ActiveRecord::Relation) }
    def team_actor_user_roles
      user_roles_query.where(actor_type: "Team")
    end

    sig { returns(T::Array[Integer]) }
    def team_ids_granted_direct_user_roles
      team_actor_user_roles.distinct.pluck(:actor_id)
    end

    sig { returns(T::Array[Integer]) }
    def team_member_ids_of_granted_teams_and_descendants
      team_ids = team_ids_granted_direct_user_roles
      return [] if team_ids.empty?

      Team.member_ids_of(team_ids, immediate_only: false)
    end

    sig { returns(ActiveRecord::Relation) }
    def user_actor_user_roles
      user_roles_query.where(actor_type: "User")
    end

    sig { returns(T::Array[Integer]) }
    def user_ids_granted_direct_user_roles
      user_actor_user_roles.distinct.pluck(:actor_id)
    end

    sig { returns(ActiveRecord::Relation) }
    def user_roles_query
      scope = UserRole.where(target_type: "Organization", target_id: @organization.id)
      scope = scope.where(role_id: visible_organization_role_ids)
      scope = scope.where(role_id: @role_ids) unless @role_ids.blank?

      scope
    end

    sig { returns(T::Array[Integer]) }
    memoize def visible_organization_role_ids
      OrganizationRole.visible_roles(@organization).map(&:id).compact
    end
  end
end
