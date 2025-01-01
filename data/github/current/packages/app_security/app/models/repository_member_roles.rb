# typed: false
# frozen_string_literal: true

class RepositoryMemberRoles
  # Public: A query object with convenience methods to obtain the direct roles
  # for the input members and all the teams in the repository. As well as for
  # the mixed roles for the input members.
  #
  # members: the members for whom to calculate the mixed roles
  # teams: the teams for whom to calculate the mixed roles
  def initialize(repository:, current_user:, members: [], teams: [])
    @repository   = repository
    @current_user = current_user
    @members      = members
    @teams        = teams
  end

  # Public: Prepopulated query object
  #
  # Returns a RepositoryMemberRoles object
  def self.fetch(repository:, current_user:, members: [], teams: [])
    new(repository: repository, current_user: current_user, members: members, teams: teams).fetch_teams_and_roles
  end

  # Public: The highest role a user has over the repository
  # if its higher that its direct role over the repository.
  #
  # Returns
  # Hash{ User => {team_role => Symbol, default_role => Symbol, org_admin => Boolean} }
  # or nil
  def mixed_role_for(user_or_team)
    mixed_role = get_mixed_role(user_or_team)

    return if mixed_role.nil?

    { team_role: mixed_role[:team_role], default_role: mixed_role[:default_role], org_admin: mixed_role[:org_admin] }
  end

  # Public: The teams which give the user the highest role over the repository
  # when the direct role the user has over the repository is lower.
  #
  # Returns an Array of Teams
  def teams_giving_mixed_role(user_or_team)
    mixed_role = get_mixed_role(user_or_team)

    return [] if mixed_role.nil?

    mixed_role.fetch(:teams, [])
  end

  # Public: The org which gives the user the default role over the repository
  # when the direct role the user has over the repository is lower.
  #
  # Returns an Organization or nil
  def org_giving_mixed_role(user_or_team)
    mixed_role = get_mixed_role(user_or_team)

    return if mixed_role.nil?
    mixed_role[:organization]
  end

  # Public: the direct role an actor (User/Team) has over a repository.
  # It can be any of: :read, :triage, :write, :maintain, :admin
  #
  # Returns a Symbol or nil
  def direct_role_for(actor)
    case actor
    when User
      direct_user_roles[actor]
    when Team
      direct_team_roles[actor]
    end
  end

  # Public: populate direct_user_roles, direct_team_roles and member_teams
  #
  # Returns the RepositoryMemberRoles object itsel
  def fetch_teams_and_roles
    direct_user_roles
    direct_team_roles
    member_teams

    self
  end

  private

  # Private: calculate which users have a role higher than their direct role
  # over a repository through one or more teams or an Organization Base Role.
  # Only entries with mixed roles are added to the resulting Hash.
  #
  # Returns a Hash{ User => {team_role => Symbol, teams => [Team], org_admin => Boolean, default_role => Symbol, organization => Organization} }
  def mixed_roles_for_users
    return @mixed_roles_for_users if defined?(@mixed_roles_for_users)

    # There are no means for users to get mixed roles in user owned repos
    unless @repository.in_organization?
      @mixed_roles_for_users = {}
      return @mixed_roles_for_users
    end

    # This fetches all organization admins for the repository's organization
    org_admin_ids = @repository.organization.admins.pluck(:id)

    @mixed_roles_for_users = @members.each_with_object({}) do |user, result|
      next unless user.instance_of?(User)

      user_role = direct_user_roles[user]
      next if user_role.nil?
      # admin is the highest role a user can get, so we can skip the computation
      next if user_role == :admin
      # org default repo permission doesn't apply to outside collaborators, and
      # they are converted to org members if they are added to a team
      next if outside_collaborator_ids.include?(user.id)

      # if it's a custom role get the base role's name
      if !Role.valid_system_role?(user_role)
        user_role = Role.base_role_name_or_self(user_role.to_s, owner: @repository.organization).to_sym
      end

      teams = []
      highest_team_role = nil
      default_org_role = nil

      if @repository.owner.organization?
        if org_admin_ids.include?(user.id)
          result[user] = { org_admin: true, organization: @repository.owner }
          # There is no higher permission than owner, we can skip the rest of the computation
          next
        end

        default_org_role = @repository.owner.default_repository_permission
        if ability_rank(user_role) < ability_rank(default_org_role)
          result[user] = { default_role: default_org_role, organization: @repository.owner }

          # no need to compute anything else if we already get admin here
          next if default_org_role == :admin
        end
      end

      teams_for(user).each do |team|
        team_role = direct_team_roles[team]

        # if there is no entry for the team, this means the current user can't see the team
        next if team_role.nil?

        # if it's a custom role get the base role's name
        if !Role.valid_system_role?(team_role)
          team_role = Role.base_role_name_or_self(team_role.to_s, owner: @repository.organization).to_sym
        end

        # if we encounter a new higher role, update the tracking vars
        if highest_team_role.nil? || ability_rank(team_role) > ability_rank(highest_team_role)
          teams.clear
          highest_team_role = team_role
        end

        # if the role has the same ranking as the highest conflicting role, add it to the tracking vars
        if ability_rank(team_role) == ability_rank(highest_team_role) &&
          ability_rank(team_role) > ability_rank(user_role)
          teams << team
        end

        next if teams.empty?
        # if we already have a Hash for that User from a Org Default Permission, we want to only update it and not override it
        if result.has_key?(user)
          result[user][:teams] = teams
          if result[user][:team_role].nil? || ability_rank(highest_team_role) > ability_rank(result[user][:team_role])
            result[user][:team_role] = highest_team_role
          end
        else
          result[user] = { teams: teams, team_role: team_role }
        end
      end
    end
  end

  # Return the highest role for a team of it, or it's ancestors.
  #
  # Returns a Hash{ Team => {team_role => Symbol, teams => [Team]} }
  def mixed_roles_for_teams
    return @mixed_roles_for_teams if defined?(@mixed_roles_for_teams)

    @mixed_roles_for_teams = @teams.each_with_object({}) do |team, mixed_role_hash|
      next unless team.instance_of?(Team)
      # we only care about child teams for mixed roles
      next unless team.ancestors?

      team_role = direct_team_roles[team]
      next if team_role.nil?
      # admin is the highest role a team can get, so we can skip the computation
      next if team_role == :admin

      # if it's a custom role get the base role's name
      if !Role.valid_system_role?(team_role)
        team_role = Role.base_role_name_or_self(team_role.to_s, owner: team.organization).to_sym
      end

      parent_teams = []
      highest_team_role = team_role

      team.ancestors.each do |ancestor|
        ancestor_role = direct_team_roles[ancestor]

        next if ancestor_role.nil?

        # if it's a custom role get the base role's name
        if !Role.valid_system_role?(ancestor_role)
          ancestor_role = Role.base_role_name_or_self(ancestor_role.to_s, owner: team.organization).to_sym
        end

        # if we encounter a new higher role, update the tracking vars
        if ability_rank(ancestor_role) > ability_rank(highest_team_role)
          parent_teams.clear
          highest_team_role = ancestor_role
        end

        # if the role has the same ranking as the highest conflicting role, add it to the tracking vars
        if ability_rank(ancestor_role) == ability_rank(highest_team_role) &&
          ability_rank(ancestor_role) > ability_rank(team_role)
          parent_teams << ancestor
        end

        next if parent_teams.empty?
        mixed_role_hash[team] = { team_role: highest_team_role, teams: parent_teams }
      end
    end
  end

  # Private: Preloaded direct roles for the users with access to this repository.
  #
  # Returns a Hash{User => Symbol}
  def direct_user_roles
    return @direct_user_roles if defined?(@direct_user_roles)

    @direct_user_roles = @repository.direct_roles_for(@members, actor_type: "User")
  end

  # Private: Preloaded direct roles for the teams with access to this repository.
  #
  # Returns a Hash{Team => Symbol}
  def direct_team_roles
    return @direct_team_roles if defined?(@direct_team_roles)

    teams = @repository.visible_teams_for(@current_user)
    if @repository.organization&.business&.enterprise_teams_org_roles_supported? && @repository.organization&.business&.feature_enabled?(:enterprise_teams_crud)
      @direct_team_roles = @repository.direct_roles_for(teams, actor_type: %w(Team BusinessTeam))
    else
      @direct_team_roles = @repository.direct_roles_for(teams)
    end
  end

  # Private: Preload Team records for the given member User records.
  #
  # Returns a Hash{user_id Integer => [Team]}
  def member_teams
    return @member_teams if defined?(@member_teams)
    @member_teams = Hash.new { |h, k| h[k] = [] }

    actor_ids = @members.map(&:ability_id)
    teams = @repository.visible_teams_for(@current_user).index_by(&:id)

    ::Ability.distinct.where(
      actor_type: "User",
      actor_id: actor_ids,
      subject_type: "Team",
      subject_id: @repository.actor_ids_for_team_on_repo,
    ).pluck(:actor_id, :subject_id).each do |actor_id, subject_id|
      @member_teams[actor_id] << teams[subject_id]
    end

    @member_teams
  end

  # Private: Look up Teams for the given User.
  #
  # Returns [Team].
  def teams_for(user)
    Array(member_teams[user.id])
  end

  def ability_rank(ability)
    Ability::ACTION_RANKING.fetch(ability, 0)
  end

  def get_mixed_role(user_or_team)
    case user_or_team
    when User
      mixed_roles_for_users[user_or_team]
    when Team
      mixed_roles_for_teams[user_or_team]
    end
  end

  def outside_collaborator_ids
    return @outside_collab_ids if defined?(@outside_collab_ids)
    @outside_collab_ids = @repository.outside_collaborators_ids
  end
end
