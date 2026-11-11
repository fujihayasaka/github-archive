# typed: true
# frozen_string_literal: true

class AccessGroupSetting < RepositoryGroupSetting
  TEAMS = "teams".freeze
  ROLES = "roles".freeze
  DENY = "deny".freeze
  PERMISSIONS_TO_ABILITIES = {
    "push" => "write",
    "pull" => "read",
  }

  def populate_attributes
    reset if self.value.nil?
    self.inherited ||= {}
    self.composite ||= {}
  end

  def reset
    self.value = { "#{TEAMS}": {}, "#{DENY}": [] }
  end

  def deny_team_changes
    value[DENY] |= [TEAMS]
  end

  def allow_team_changes
    value[DENY].delete(TEAMS)
  end

  def add(role, team_id)
    value[TEAMS].each do |_role, team_ids|
      team_ids.delete(team_id)
    end

    value[TEAMS][role] ||= []
    value[TEAMS][role] |= [team_id]
  end

  def teams
    composite[TEAMS] ||= []
  end

  def teams_with_role(role)
    composite[TEAMS][role] || []
  end

  # if team changes are allowed, we'll let users grant teams more permissions, but not fewer permissions
  def deny_role_change?(team_id, role)
    return true if deny_team_changes?

    # we need to convert :push to "write" and :pull to "read"
    new_role = PERMISSIONS_TO_ABILITIES[role] || role

    # we allow granting a team more permissions, but not fewer permissions
    # check role change in order of greatest permisison to least permission
    %w[admin maintain write triage read].each do |role|
      # new role has higher (or equal) permissions than current role
      return false if role == new_role.to_s

      # current role has higher permissions than new role
      return true if composite[TEAMS][role]&.include?(team_id)
    end

    # team is not defined in the setting so don't block changes
    false
  end

  def includes_team?(team_id)
    composite[TEAMS].each do |_role, team_ids|
      return true if team_ids.include?(team_id)
    end
    false
  end

  def deny_team_changes?
    composite[DENY].include?(TEAMS)
  end

  def apply(actor:, repository:)
    current_teams = Ability.where(actor_type: "Team", subject_type: "Repository", subject_id: repository.id).pluck(:action, :actor_id)
    current_hash = {}
    current_teams.each do |role, team_id|
      current_hash[role] ||= []
      current_hash[role] << team_id
    end

    processed_ids = T.let([], T::Array[T.untyped])
    desired_hash = {}

    # Teams can only have 1 role on this repo, and roles have a hierarchy. So filter duplicates.
    # IMPORTANT that these are executed in order of highest privilege to lowest privilege
    # because each team can only have one role on the repository
    %w[admin maintain write triage read].each do |role|
      team_ids = teams_with_role(role)
      team_ids = team_ids - processed_ids
      processed_ids = processed_ids + team_ids
      desired_hash[role] = team_ids
      current_hash[role] ||= []
    end

    teams_to_add = {}
    teams_to_remove = {}

    desired_hash.each do |role, team_ids|
      teams_to_add[role] = team_ids - current_hash[role]
      teams_to_remove[role] = current_hash[role] - team_ids
    end

    teams_to_remove.each do |_role, team_ids|
      team_ids.each do |team_id|
        team = Team.find(team_id)
        repository.remove_team(team)
      end
    end

    teams_to_add.each do |role, team_ids|
      team_ids.each do |team_id|
        team = Team.find(team_id)
        repository.add_team(team, action: role)
      end
    end
  end
end
