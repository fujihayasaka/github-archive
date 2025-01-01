# typed: strict
# frozen_string_literal: true

module RoleAssignments
  class FetchRoleAssignments
    include GitHub::Memoizer

    sig { returns(T.any(Business, Organization)) }
    attr_reader :target

    PAGE_SIZE = 10

    sig do
      params(target: T.any(Business, Organization), query: T.nilable(String), stafftools: T::Boolean).void
    end
    def initialize(target:, query: nil, stafftools: false)
      @target = target
      sanitized_query = query.present? ? ActiveRecord::Base.sanitize_sql_like(query.strip) : nil
      @query = T.let(sanitized_query, T.nilable(String))
      @stafftools = stafftools
    end

    sig { params(page: Integer).returns(T::Array[Types::ActorRoleAssignment]) }
    def paginate_user_role_assignments(page:)
      return [] if target.is_a?(Business) && !T.cast(target, Business).custom_enterprise_roles_supported?
      return [] if target.is_a?(Organization) && !T.cast(target, Organization).business&.enterprise_teams_org_roles_supported?

      # loads users with directly and indirectly assigned roles on the target
      users = users_relation.order(:login).paginate(page:, per_page: PAGE_SIZE).index_by(&:id)

      # Creates a hash of actor_id => [subject_id], where actor_id == user_id, and subject_id == team_id
      # This represents all the teams a given user is a member of and their ancestors
      # TODO: ensure this works for nested business teams when implemented
      team_memberships = team_and_business_team_memberships_by_user_id.slice(*users.keys)
      team_ids = team_memberships.values.flatten.uniq
      teams = Orgs.domain.teams.teams_by_ids(team_ids).index_by(&:id)

      users.map do |user_id, user|
        role_assignments_by_role_id = {}

        # Add all directly assigned roles
        direct_user_roles_by_user_id[user_id]&.each do |user_role|
          next unless (role = available_roles[user_role.role_id])

          role_assignments_by_role_id[user_role.role_id] = Types::RoleAssignment.new(
            role: role,
            directly_assigned: true,
          )
        end

        # Iterate through the teams the user is a member of (and their ancestors), and add any roles assigned to those teams
        team_memberships[user_id]&.each do |team_id|
          next unless (team = teams[team_id])

          direct_user_roles_by_team_and_business_team_id[team_id]&.each do |user_role|
            next unless (role = available_roles[user_role.role_id])

            # If there is no existing role assignment for this role, it means the user is not directly assigned to it
            # and we need to create a new RoleAssignment object
            role_assignments_by_role_id[user_role.role_id] ||= Types::RoleAssignment.new(
              role: role,
              directly_assigned: false,
            )
            role_assignments_by_role_id[user_role.role_id].indirect_assignments << Types::IndirectAssignmentSource.from_team(team, owner: contextual_owner_for(team.type), stafftools: @stafftools)
          end
        end

        Types::ActorRoleAssignment.new(
          actor: Types::Actor.from_model(user),
          role_assignments: role_assignments_by_role_id.values,
        )
      end
    end

    sig { params(page: Integer).returns(T::Array[Types::ActorRoleAssignment]) }
    def paginate_business_team_role_assignments(page:)
      return [] if target.is_a?(Business) && !business_teams_enabled?
      return [] if target.is_a?(Organization) && !T.cast(target, Organization).business&.enterprise_teams_org_roles_supported?

      teams = business_team_relation.order(:name).paginate(page:, per_page: PAGE_SIZE).index_by(&:id)

      teams.map do |team_id, team|
        role_assignments_by_role_id = {}

        direct_user_roles_by_business_team_id[team_id]&.each do |team_role|
          next unless (role = available_roles[team_role.role_id])

          role_assignments_by_role_id[team_role.role_id] = Types::RoleAssignment.new(
            role: role,
            directly_assigned: true,
            indirect_assignments: [], # Business teams can't be nested yet, thus have no indirect assignments
          )
        end

        Types::ActorRoleAssignment.new(
          actor: Types::Actor.from_model(team),
          role_assignments: role_assignments_by_role_id.values,
        )
      end
    end

    sig { params(page: Integer).returns(T::Array[Types::ActorRoleAssignment]) }
    def paginate_team_role_assignments(page:)
      return [] if target.is_a?(Business)
      return [] if target.is_a?(Organization) && !T.cast(target, Organization).business&.enterprise_teams_org_roles_supported?

      # load team and business teams that have or inherit a role assigned to the target
      teams = teams_relation
        .order(:name)
        .paginate(page: page, per_page: PAGE_SIZE)
        .index_by(&:id)

      indirect_roles = indirect_user_roles_by_descendant_id(teams.keys)

      teams.map do |team_id, team|
        role_assignments_by_role_id = {}

        # create/update assignment for roles directly assigned to team
        direct_user_roles_by_team_and_business_team_id[team_id]&.each do |team_role|
          next unless (role = available_roles[team_role.role_id])

          # create a new assignment
          role_assignments_by_role_id[team_role.role_id] = Types::RoleAssignment.new(
            role: role,
            directly_assigned: true,
            indirect_assignments: [],
          )
        end

        # create/update assignment for roles indirectly assigned to teams
        indirect_roles[team_id]&.each do |team_role|
          next unless (role = available_roles[team_role.role_id])

          # the source of this indirect assignment is the actor of the UserRole
          # we've plucked and memoized the data required to create the sources to reduce queries
          directly_assigned_team = T.must(indirect_assignment_sources[team_role.actor_id])
          directly_assigned_team[:owner] = owner_for(directly_assigned_team[:type])
          indirect_assignment_source = Types::IndirectAssignmentSource.from_team_details(**T.unsafe(directly_assigned_team), stafftools: @stafftools)

          if assignment = role_assignments_by_role_id[team_role.role_id]
            # if an assignment exists, add a new indirect assignment source
            assignment.indirect_assignments << indirect_assignment_source
          else
            # create a new assignment
            role_assignments_by_role_id[team_role.role_id] = Types::RoleAssignment.new(
              role: role,
              directly_assigned: false,
              indirect_assignments: [indirect_assignment_source],
            )
          end
        end

        Types::ActorRoleAssignment.new(
          actor: Types::Actor.from_model(team),
          role_assignments: role_assignments_by_role_id.values,
        )
      end
    end

    sig { returns(Integer) }
    def total_user_role_assignments
      return assigned_user_ids.size if @query.blank?

      users_relation.count
    end

    sig { returns(Integer) }
    def total_team_role_assignments
      return assigned_team_ids.size if @query.blank?

      teams_relation.count
    end

    sig { returns(Integer) }
    def total_business_team_role_assignments
      return 0 unless business_teams_enabled?
      return assigned_business_team_ids.size if @query.blank?

      business_team_relation.count
    end

    private

    # Returns relation with users assigned roles matching the query if provided
    sig { returns(ActiveRecord::Relation) }
    def users_relation
      rel = User.includes(:profile).where(id: assigned_user_ids)
      rel = rel.merge(User.like_display_login_or_profile_name(@query)) if @query.present?
      rel
    end

    # Returns relation with enterprise teams assigned roles matching the query if provided
    sig { returns(ActiveRecord::Relation) }
    def business_team_relation
      rel = BusinessTeam.where(id: assigned_business_team_ids)
      rel = rel.merge(BusinessTeam.like_name(@query)) if @query.present?
      rel
    end

    # Returns relation with teams and enterprise teams assigned roles matching the query if provided
    sig { returns(ActiveRecord::Relation) }
    def teams_relation
      rel = Team.where(id: assigned_team_ids)
      rel = rel.merge(Team.like_name(@query)) if @query.present?
      rel = rel.with_business_teams
      rel
    end

    # Returns a list of user ids that have a role assigned to the target directly or via a team (and its ancestors) or a business team
    sig { returns(T::Array[Integer]) }
    memoize def assigned_user_ids
      (direct_user_roles_by_user_id.keys + team_and_business_team_memberships_by_user_id.keys).uniq
    end

    # Returns a list of business team ids that have a role assigned to the target
    sig { returns(T::Array[Integer]) }
    memoize def assigned_business_team_ids
      # Currently only consists of direct assignments
      direct_user_roles_by_business_team_id.keys
    end

    # Returns a list of team and business team ids that have or inherit a role assigned to the target
    sig { returns(T::Array[Integer]) }
    memoize def assigned_team_ids
      (direct_user_roles_by_team_and_business_team_id.keys +
        indirectly_assigned_team_ids).uniq
    end

    # Returns a list of roles which can be assigned to the target
    sig { returns(T::Hash[Integer, Types::Role]) }
    memoize def available_roles
      target
        .roles_assignable_to_target
        .map { |role| Types::Role.from_model(role) }
        .index_by(&:id)
    end

    # Returns a hash of user roles assigned to the target, grouped by actor type
    # {
    #   "BusinessTeam" => [#<UserRole>],
    #   "Team" => [#<UserRole>],
    #   "User" => [#<UserRole>]
    # }
    sig { returns(T::Hash[String, T::Array[UserRole]]) }
    memoize def directly_assigned_user_roles
      UserRole
        .select(:actor_id, :actor_type, :role_id)
        .where(role_id: available_roles.keys, target_type: target.class.name, target_id: target.id)
        .group_by(&:actor_type)
    end

    # Returns a hash of user roles assigned to the target for user actors grouped by user id
    # { user_id => [#<UserRole>] }
    sig { returns(T::Hash[Integer, T::Array[UserRole]]) }
    memoize def direct_user_roles_by_user_id
      directly_assigned_user_roles.fetch("User", []).group_by(&:actor_id)
    end

    # Returns a hash of user roles assigned to the target for business team actors grouped by business team id
    # { business_team_id => [#<UserRole>] }
    sig { returns(T::Hash[Integer, T::Array[UserRole]]) }
    memoize def direct_user_roles_by_business_team_id
      # don't return roles unless the feature is enabled
      return {} unless business_teams_enabled?

      directly_assigned_user_roles.fetch("BusinessTeam", []).group_by(&:actor_id)
    end

    # Returns a hash of user roles assigned to the target for business team actors grouped by team id
    # excludes descendant teams
    # { team_id => [#<UserRole>] }
    sig { returns(T::Hash[Integer, T::Array[UserRole]]) }
    memoize def direct_user_roles_by_team_id
      # returns {} for enterprise roles which can't be assigned to teams
      directly_assigned_user_roles.fetch("Team", []).group_by(&:actor_id)
    end

    # Returns a list of team and business team ids which directly have a role assigned to the target
    sig { returns(T::Hash[Integer, T::Array[UserRole]]) }
    memoize def direct_user_roles_by_team_and_business_team_id
      direct_user_roles_by_business_team_id
        .merge(direct_user_roles_by_team_id)
    end

    # Returns team ids and business team ids grouped by member id (including indirect Team memberships)
    # TODO: ensure this works with nested business teams when implemented
    # { user_id: [team_1_id, team_2_id] }
    sig { returns(T::Hash[Integer, T::Array[Integer]]) }
    memoize def team_and_business_team_memberships_by_user_id
      directly_assigned_ids = direct_user_roles_by_team_and_business_team_id.keys
      Team.descendant_or_self_memberships_indexed_by_member_id(directly_assigned_ids, with_business_teams: true)
    end

    # Returns a hash of teams and their descendant teams
    # { ancestor_team_id => [child_team_id, grandchild_team_id] }
    sig { returns(T::Hash[Integer, T::Array[Integer]]) }
    memoize def team_descendant_hash
      teams = Team.where(id: direct_user_roles_by_team_id.keys)

      Platform::Loaders::TeamDescendants.load_all(teams, immediate_only: false).sync
    end

    # Returns a list of team ids which inherit from the teams directly assigned roles
    sig { returns(T::Array[Integer]) }
    memoize def indirectly_assigned_team_ids
      team_descendant_hash.values.flatten.uniq
    end

    # Returns a hash of indirectly assigned user roles by the inheriting team id
    # Includes roles which are also directly assigned to the inheriting team
    # { descendant_team_id => [#<UserRole>] }
    sig { params(team_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[UserRole]]) }
    def indirect_user_roles_by_descendant_id(team_ids)
      # restructures the hash to map user roles by the inheriting team id
      # { descendant_team_id => [#<UserRole>] }
      team_descendant_hash.each_with_object({}) do |(ancestor, descendants), hash|
        descendants.each do |descendant|
          next unless team_ids.include?(descendant)
          next if descendant == ancestor
          (hash[descendant] ||= []).concat(direct_user_roles_by_team_id[ancestor])
        end
        hash
      end
    end

    sig { returns(T::Hash[Integer, T::Hash[Symbol, T.untyped]]) }
    memoize def indirect_assignment_sources
      Team
        .with_business_teams
        .where(id: direct_user_roles_by_team_id.keys)
        .pluck(:id, :name, :slug, :type)
        .each_with_object({}) { |(id, name, slug, type), hash| hash[id] = { id:, name:, slug:, type: }; hash }
    end

    sig { returns(T.nilable(Business)) }
    memoize def business_for_target
      target.is_a?(Business) ? T.cast(target, Business) : T.cast(target, Organization).business
    end

    sig { params(team_type: String).returns(T.any(Business, Organization)) }
    def owner_for(team_type)
      team_type == "BusinessTeam" ? T.must(business_for_target) : target
    end

    sig { params(team_type: String).returns(T.any(Business, Organization)) }
    def contextual_owner_for(team_type)
      # We want to display business teams as organization team links if the user is viewing the organization
      if target.is_a?(Organization) && !@stafftools && business_team_org_assignment_enabled?
        target
      else
        owner_for(team_type)
      end
    end

    # Returns true if the target has the ETv2 FF enabled
    sig { returns(T::Boolean) }
    memoize def business_teams_enabled?
      !!business_for_target&.erp_feature_enabled?(:enterprise_teams_crud)
    end

    # Returns true if the target has the ETv2 M2 FF enabled
    sig { returns(T::Boolean) }
    memoize def business_team_org_assignment_enabled?
      !!business_for_target&.erp_feature_enabled?(:enterprise_teams_org_assignment)
    end
  end
end
