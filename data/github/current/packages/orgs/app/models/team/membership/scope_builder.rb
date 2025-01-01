# typed: true
# frozen_string_literal: true

# This class is used to build search scopes for team members.
# Given the flexibility it provides, ensuring it performs well is
# very hard. For huge teams with specific query filters this
# builder likely performs badly. This is why it's not recommended
# to add additional usages of this builder with this kind of
# flexibility.
class Team::Membership
  class ScopeBuilder

    attr_reader :team_id, :viewer, :membership, :role, :query, :order, :pagination, :max_members_limit

    # The pagination argument here can pass in first / last / before / after arguments
    # that will optimize building the scope here to reduce the number of abilities we
    # have to retrieve before building the User scope.
    def initialize(team_id:, viewer:, membership: nil, role: nil, query: nil, pagination: {}, max_members_limit: nil, with_business_teams: false)
      @team_id    = team_id
      @viewer     = viewer

      @membership = membership&.to_sym
      @role = role&.to_sym
      @query = query
      @pagination = pagination
      @max_members_limit = max_members_limit
      @with_business_teams = with_business_teams
    end

    def count
      if count_abilities?
        abilities_scope.count(:actor_id)
      else
        scope.count
      end
    end

    def scope
      #NOTE: if max_members_limit is nil then limit(nil) is a no-op
      team_member_ids = abilities_scope.limit(max_members_limit).pluck(:actor_id)
      return User.none if team_member_ids.empty?

      team_member_ids = team_member_ids.sort

      if pagination[:after]
        after = pagination[:after]
        team_member_ids.select! { |id| id > after }
      end

      if pagination[:before]
        before = pagination[:before]
        team_member_ids.select! { |id| id < before }
      end

      if pagination[:first]
        team_member_ids = team_member_ids.take(pagination[:first] + 1)
      end

      if pagination[:last]
        team_member_ids = team_member_ids.reverse.take(pagination[:last] + 1)
      end

      # Users who are members of the team
      scope = User.where(id: team_member_ids)

      # Search for user/login profile query term
      if query.present?
        term = sanitized_sql_like(query)
        scope = scope.joins("LEFT JOIN profiles ON profiles.user_id = users.id")
                      .where("(users.login LIKE ? OR profiles.name LIKE ?)", term, term)
      end

      # All the joins mean we may have multiple user rows either because:
      # - they have multiple profiles, and we have joined profiles to search their username for query
      # - we are querying for members of child teams, and a user is a member of multiple child teams
      scope = scope.distinct
    end

    # This is the REST API version of scope which is simpler and doesn't implement the same pagination and query
    def paged_scope(page:, per_page:)
      team_member_ids = abilities_scope.offset((page - 1) * per_page).limit(per_page).order(:actor_id).pluck(:actor_id)
      total_count = abilities_scope.select(:actor_id).count

      # Users who are members of the team
      WillPaginate::Collection.create(page, per_page, total_count) do |pager|
        pager.replace(User.where(id: team_member_ids).order(:id))
      end
    end

    def abilities_scope
      subject_type = @with_business_teams ? %w(Team BusinessTeam) : "Team"
      scope = ::Ability.where(subject_type: subject_type, subject_id: team_id, actor_type: "User")
      scope = priority_clause_for_membership(scope, membership)

      role_action = ability_action_from_role(role)

      if role_action
        team = ::Team.find(team_id)
        join_org_role = <<-SQL
          LEFT JOIN abilities org_role_ab
            ON org_role_ab.actor_id = abilities.actor_id
            AND org_role_ab.actor_type = 'User'
            AND org_role_ab.subject_type = 'Organization'
            AND org_role_ab.priority = ?
            AND org_role_ab.action = ?
            AND org_role_ab.subject_id = ?
          /* abilities-join-audited */
        SQL
        scope = scope.joins(sanitize_sql_array([join_org_role, ::Ability.priorities[:direct], ::Ability.actions[:admin], team.organization_id]))

        if role == :maintainer
          # Add any org admins to the list here
          scope = scope.where("(abilities.action = ? OR org_role_ab.subject_id IS NOT NULL)", role_action)
        else
          # If non maintainer, remove any org admin ids
          scope = scope.where("(abilities.action = ? AND org_role_ab.subject_id IS NULL)", role_action)
        end
      end

      scope.distinct
    end

    private

    def count_abilities?
      # We can count with abilities if the query is nil and we don't
      # need custom filtering on the users returned after abilities
      query.nil?
    end

    def sanitized_sql_like(search_term)
      "\%#{::ActiveRecord::Base.sanitize_sql_like(search_term)}\%"
    end

    def sanitize_sql_array(query_array)
      ::ActiveRecord::Base.send(:sanitize_sql_array, query_array)
    end

    # Internal: translates between the world of team "roles" and ablity
    # "actions".
    #
    # Organization owners are also considered team maintainers, but we
    # account for those users directly in the abilities query (see #fetch
    # method).
    #
    # Returns an Integer representing the correct Ability action for a role.
    def ability_action_from_role(role)
      case role
      when :member then ::Ability.actions[:read]
      when :maintainer then ::Ability.actions[:admin]
      end
    end

    # Internal: maps between team "membership" type and ability "priority"
    # SQL condition
    #
    # membership - One of either :immediate, :child_team or nil
    #
    # Returns a String.
    def priority_clause_for_membership(scope, membership)
      priority = ::Ability.priorities[:direct]

      case membership
      when :immediate then scope.where("abilities.priority = ?", priority)
      when :child_team then scope.where("abilities.priority < ?", priority)
      else
        scope.where("abilities.priority <= ?", priority)
      end
    end
  end
end
