# typed: strict
# frozen_string_literal: true

module RoleAssignmentList
  class OrgRoleAssignments
    include GitHub::Memoizer

    sig { returns(T::Array[RoleAssignmentList::RoleAssignment]) }
    attr_accessor :assignments

    sig do
      params(
        organization: Organization,
        actor_type: String,
        direct_only: T::Boolean,
        role_ids: T::Array[T.nilable(Integer)],
        fetch_user_assignments: T::Boolean,
        fetch_team_assignments: T::Boolean,
      ).void
    end
    def initialize(organization:, actor_type:, direct_only: true, role_ids: [], fetch_user_assignments: true, fetch_team_assignments: true)
      raise ArgumentError, "actor_type must be User or Team" unless %w(User Team).include?(actor_type)
      @organization = organization
      @assignments = T.let([], T::Array[RoleAssignmentList::RoleAssignment])
      @direct_only = direct_only
      @actor_type = actor_type
      @role_ids = T.let(role_ids.compact, T::Array[Integer])
      @user_direct_assignments = T.let([], T::Array[UserRole])
      @teams_by_id = T.let({}, T::Hash[Integer, Team])
      @users_by_id = T.let({}, T::Hash[Integer, User])
      @team_descendants = T.let({}, T::Hash[Integer, T::Array[Integer]])
      @fetch_user_assignments = fetch_user_assignments
      @fetch_team_assignments = fetch_team_assignments
      fetch_assignments(actor_type)
    end

    sig { returns(T::Array[Integer]) }
    def assignee_ids
      return [] if assignments.blank?
      assignments.map { |assignment| assignment.actor.id }.uniq.compact
    end

    sig { returns(T::Array[T.any(User, Team)]) }
    memoize def assignees
      return [] if assignments.blank?
      if actor_type == "User"
        T.cast(assignments.map(&:actor), T::Array[User]).uniq.sort_by(&:display_login)
      else
        T.cast(assignments.map(&:actor), T::Array[Team]).uniq.sort_by { |t| T.must(t.name) }
      end
    end

    sig { returns(T::Array[Integer]) }
    def user_assignee_ids
      return user_direct_assignment_ids if direct_only?

      assignees = user_direct_assignment_ids + indirect_user_assignee_ids
      assignees.uniq
    end

    sig { returns(T::Array[Integer]) }
    def team_assignee_ids
      return team_direct_assignment_ids if direct_only?

      assignees = team_direct_assignment_ids + inherited_team_assignee_ids
      assignees.uniq
    end

    private

    sig { params(actor_type: String).void }
    def fetch_assignments(actor_type)
      start_time = GitHub::Dogstats.monotonic_time
      case actor_type
      when "User"
        fetch_user_assignments
      when "Team"
        fetch_team_assignments
      end

      tags = {
        organization_id: @organization.id,
        assignments_count: (@assignments.size / 100.0).ceil * 100, # Round up to the next 100,
        fetch_user_assignments: fetch_user_assignments?,
        fetch_team_assignments: fetch_team_assignments?
      }.map { |k, v| "#{k}:#{v}" }

      GitHub.dogstats.distribution_timing_since("org_role_assignments_#{actor_type.downcase}_fetch.dist", start_time, tags: tags)
    end

    sig { returns(T::Array[UserRole]) }
    memoize def fetch_user_roles
      visible_roles = OrganizationRole.visible_roles(@organization)
      user_roles = UserRole.eager_load(:role).where(target_type: "Organization", target_id: @organization.id)
      user_roles = user_roles.where(role_id: visible_roles.pluck(:id))
      user_roles = user_roles.where(role_id: @role_ids) unless @role_ids.blank?
      user_roles = user_roles.to_a

      user_roles
    end

    sig { returns(T::Boolean) }
    private def fetch_user_assignments?
      @fetch_user_assignments
    end

    sig { void }
    private def fetch_user_assignments
      return if !fetch_user_assignments?
      return if fetch_user_roles.blank?

      # Load all the users teams into the @users_by_id cache
      hydrate_users(user_ids_to_load: user_direct_assignment_ids)

      # Populate the direct user assignments
      user_direct_assignments.each do |uda|
        @assignments << RoleAssignment.new(actor: find_user_by_actor_id(uda.actor_id), role: T.must(uda.role))
      end

      return if direct_only?
      fetch_indirect_user_assignments
    end

    # Fetch indirect user assignments through membership in teams that are assigned or inherit a role
    sig { void }
    def fetch_indirect_user_assignments
      return if team_direct_assignment_ids.blank?

      # Fetch all indirect user memberships in teams that are assigned to roles
      # parent in this context reflects the team the user is a direct member of, which indirectly grants
      # membership to the team that is actually assigned the role
      team_memberships = Ability.where(subject_type: "Team", subject_id: team_direct_assignment_ids, actor_type: "User").eager_load(:parent).to_a
      return if team_memberships.blank?

      # collect the direct and indirect memberships in teams that are assigned to roles by assigned team id
      membership_by_parent = team_memberships.group_by(&:subject_id)

      indirect_user_ids = T.let([], T::Array[Integer])

      team_ids = team_direct_assignment_ids
      team_memberships.each do |ability|
        indirect_user_ids << ability.actor_id
        team_ids << T.must(ability.parent).subject_id if ability.priority == "indirect"
      end

      indirect_users = hydrate_users(user_ids_to_load: indirect_user_ids)
      teams = hydrate_teams(team_ids_to_load: team_ids)

      team_direct_assignments.each do |td|
        # for every team that is assigned, find the users who are directly and indirectly members of those teams
        assigned_team = find_team_by_actor_id(td.actor_id)
        user_memberships = membership_by_parent.fetch(T.must(assigned_team.id), [])
        next if user_memberships.empty?

        # if the user is a member of a child team of the assigned team, the ability record will have an indirect priority
        # and have a parent_id linking to the direct membership
        user_memberships.each do |m|
          member_of = m.priority == "direct" ? assigned_team : find_team_by_actor_id(T.must(m.parent).subject_id)
          user = find_user_by_actor_id(m.actor_id)
          @assignments << RoleAssignment.new(actor: user, role: T.must(td.role), assigned_team: assigned_team, through: member_of)
        end
      end
    end

    sig { returns(T::Boolean) }
    def fetch_team_assignments?
      @fetch_team_assignments
    end

    sig { void }
    def fetch_team_assignments
      return if !fetch_team_assignments?
      return if team_direct_assignment_ids.blank?

      # Load all the child teams into the @teams_by_id cache
      hydrate_teams(team_ids_to_load: team_direct_assignment_ids)

      osm_role = Role.security_manager_role
      enterprise_managed_by_team_id =
        if (
          ::SecurityCenter::FeatureFlagHelper.show_security_manager_in_org_role_assignment?(actor: @organization) &&
          team_direct_assignments.any? { |user_role| user_role.role == osm_role } # Only OSM can be enterprise managed today
        )
          @teams_by_id \
            .map { |team_id, team| [team_id, team.async_enterprise_team_managed?] }
            .map { |team_id, promise| promise.then { |managed| [team_id, managed] } }
            .then { |promises| Promise.all(promises) }
            .sync
            .to_h
        else
          Hash.new(false)
        end

      team_direct_assignments.each do |user_role|
        role = T.must(user_role.role)

        # Right now only the organization security manager role assignment is enterprise managed
        # and only for enterprise teams with the enterprise security manager role.
        # As enterprise teams and enterprise roles are developed further,
        # this will need to be revisited.
        enterprise_managed = false
        if enterprise_managed_by_team_id[user_role.actor_id] && role == osm_role
          enterprise_team = @teams_by_id[user_role.actor_id]&.enterprise_team_organization_mapping&.enterprise_team
          enterprise_managed = !!(enterprise_team && ::SecurityProduct::EnterpriseSecurityManagerRole.granted?(enterprise_team))
        end

        @assignments << RoleAssignment.new(actor: find_team_by_actor_id(user_role.actor_id), role:, enterprise_managed:)
      end

      return if direct_only?
      fetch_inherited_team_assignments
    end

    sig { void }
    def fetch_inherited_team_assignments
      # find all the children of each assigned team
      team_descendant_ids = fetch_team_descendant_ids
      return if team_descendant_ids.blank?

      # Load all the child teams into the @teams_by_id cache
      hydrate_teams(team_ids_to_load: team_descendant_ids.values.flatten.uniq)

      # add RoleAssignment records for each child of an assigned team
      team_direct_assignments.each do |user_role|
        assigned_team = find_team_by_actor_id(user_role.actor_id)
        inherited_team_ids = team_descendant_ids.fetch(user_role.actor_id)
        next if inherited_team_ids.blank?
        inherited_team_ids.each do |team_id|
          # Work around the Team Descendant loader reporting that a child has itself as a descendant.
          next if team_id == assigned_team.id
          inherited_team = find_team_by_actor_id(team_id)
          @assignments << RoleAssignment.new(actor: inherited_team, role: T.must(user_role.role), assigned_team: assigned_team)
        end
      end
    end

    # Returns user objects for a list of user_ids and also caches the results
    sig { params(user_ids_to_load: T::Array[Integer]).returns(T::Array[User]) }
    def hydrate_users(user_ids_to_load:)
      return [] if user_ids_to_load.blank?
      known_user_ids = @users_by_id.keys

      missing_user_ids = user_ids_to_load - known_user_ids
      result = User.batched_scope(:id, values: missing_user_ids.uniq).to_a

      @users_by_id.merge!(result.to_h { |user| [T.must(user.id), user] }) unless result.blank?
      T.unsafe(@users_by_id).fetch_values(*user_ids_to_load) { nil }.compact
    end

    # Returns team objects for a list of team_ids and also caches the results
    sig { params(team_ids_to_load: T::Array[Integer]).returns(T::Array[Team]) }
    def hydrate_teams(team_ids_to_load:)
      return [] if team_ids_to_load.blank?

      known_team_ids = @teams_by_id.keys
      missing_team_ids = team_ids_to_load - known_team_ids
      result = Team.batched_scope(:id, values: missing_team_ids.uniq).to_a

      @teams_by_id.merge!(result.to_h { |team| [T.must(team.id), team] }) unless result.blank?
      T.unsafe(@teams_by_id).fetch_values(*team_ids_to_load) { nil }.compact
    end

    sig { returns(T::Array[Integer]) }
    def indirect_user_assignee_ids
      return [] if team_direct_assignments.blank?

      team_ids = team_direct_assignments.map(&:actor_id)
      Ability.where(subject_type: "Team", subject_id: team_ids, actor_type: "User").pluck(:actor_id)
    end

    sig { returns(T::Array[Integer]) }
    def inherited_team_assignee_ids
      team_descendants = fetch_team_descendant_ids
      team_descendants.values.flatten
    end

    sig { returns(T::Boolean) }
    def direct_only?
      @direct_only
    end

    sig { returns(String) }
    def actor_type
      @actor_type
    end

    sig { returns(T::Array[UserRole]) }
    memoize def user_direct_assignments
      # users directly assigned to roles
      fetch_user_roles.select { |ur| ur.actor_type == "User" }
    end

    sig { returns(T::Array[Integer]) }
    memoize def user_direct_assignment_ids
      return [] if user_direct_assignments.blank?

      user_direct_assignments.map(&:actor_id).uniq
    end

    sig { returns(T::Array[UserRole]) }
    memoize def team_direct_assignments
      # teams directly assigned to roles
      fetch_user_roles.select { |ur| ur.actor_type == "Team" }
    end

    sig { returns(T::Array[Integer]) }
    memoize def team_direct_assignment_ids
      return [] if team_direct_assignments.blank?

      team_direct_assignments.map(&:actor_id).uniq
    end

    sig { returns(T::Hash[Integer, T::Array[Integer]]) }
    memoize def fetch_team_descendant_ids
      teams = hydrate_teams(team_ids_to_load: team_direct_assignment_ids)
      Platform::Loaders::TeamDescendants.load_all(teams, immediate_only: false).sync
    end

    sig { params(actor_id: Integer).returns(User) }
    def find_user_by_actor_id(actor_id)
      @users_by_id.fetch(actor_id) { User.find_by!(id: actor_id) }
    end

    sig { params(actor_id: Integer).returns(Team) }
    def find_team_by_actor_id(actor_id)
      @teams_by_id.fetch(actor_id) { Team.find_by!(id: actor_id) }
    end
  end
end
