# typed: true
# frozen_string_literal: true

class Organization::RepositoryPermissions
  include Scientist

  def initialize(repo, user)
    @repo = repo
    @user = user

    if organization.nil?
      raise ArgumentError,
        "Must be used on a org-owned repo or a fork of an org-owned repo"
    end
  end

  def all_team_abilities_for_repository
    # Based on most_capable_team_abilities_for_repository, but returns all team abilities
    team_abilities_for_repository.flat_map { |ability| derived_abilities_for(ability) }
  end

  # Public: Get the highest permission that the user has on the repo.
  #
  # Returns a Symbol (:read, :write, or :admin).
  def active_permission
    return @active_permission if defined? @active_permission

    @active_permission = @repo.access_level_for(@user)
  end

  # Public: Get all the abilities that are giving the user their highest
  # permission on the repo.
  #
  # Returns an Array of Abilities.
  def active_abilities
    abilities_by_permission[active_permission] || []
  end

  # Public: Get all the abilities that are giving the user a permission lower
  # than the active permission on the repo.
  #
  # Returns an Array of Abilities.
  def inactive_abilities
    @inactive_abilities ||= begin
      inactive_permissions = abilities_by_permission.keys - [active_permission]
      abilities_by_permission.values_at(*inactive_permissions).flatten
    end
  end

  # Public: Get all the abilities that are giving the user read access
  #
  # Returns an Array of Abilities.
  def read_abilities
    abilities_by_permission[:read].dup
  end

  # Public: Get all the abilities that are giving the user write access
  #
  # Returns an Array of Abilities.
  def write_abilities
    abilities_by_permission[:write].dup
  end

  # Public: Get all the abilities that are giving the user admin access
  #
  # Returns an Array of Abilities.
  def admin_abilities
    abilities_by_permission[:admin].dup
  end

  # Public: Get the user's direct (collaboration) ability on the repo, or nil if
  # the user only has access to the repo through teams.
  #
  # Returns an Ability or nil.
  def direct_ability
    return @direct_ability if defined? @direct_ability

    @direct_ability =
      if ability = Authorization.service.direct_ability_between(actor: @user, subject: @repo)
        DerivedAbility.new(ability)
      end
  end

  # Public: Get the organization's ability on the repo. This ability represents
  # the organization's default repository permission.
  #
  # This will return nil if any of these are true:
  # - The organization has no default repository permission.
  # - The user is not a member of the organization.
  #
  # Returns a DerivedAbility or nil.
  def organization_ability
    return @organization_ability if defined? @organization_ability
    return unless organization.member?(@user)

    @organization_ability =
      if ability = Authorization.service.most_capable_ability_between(actor: organization, subject: @repo)
        DerivedAbility.new(ability)
      end
  end

  # Public: Is the user's direct (collaboration) ability on the repo active?
  #
  # Returns true if the user's direct ability on the repo is active, or false if
  # it's inactive or doesn't exist
  def direct_ability_active?
    direct_ability.present? && direct_ability.action.to_sym == active_permission
  end

  # Public: Revoke all of the user's permissions on the repo. After calling this
  # method, the user will have no access to the repo (aside from :read if it's
  # a public repo).
  #
  # Returns nothing.
  def revoke_all(actor: @repo.owner)
    @repo.remove_member(@user, actor)
    user_teams_with_access.each { |team| team.remove_member(@user) }
  end

  # Public: Revoke all sources of the user's active permission on the repo.
  # After calling this method, the user's new active permission will be the
  # highest of their previously-inactive permissions.
  #
  # For example, if the user is on a team that gives them :admin on the repo and
  # another team that gives them :write, and this method is called, they'll be
  # removed from the team that was giving them :admin, leaving them with :write.
  def revoke_active(actor: @repo.owner)
    @repo.remove_member(@user, actor) if direct_ability_active?
    active_teams.each { |team| team.remove_member(@user) }
  end

  # Public: Get all the teams giving the user access to the repo (includes
  # inherited permissions).
  #
  # Returns an Array of Teams.
  def user_teams_with_access
    @user_teams_with_access ||= user_teams.select do |team|
      team_and_ancestor_ids_with_access.intersect?(team.id_and_ancestor_ids.to_set)
    end
  end

  # Public: Get all the teams giving the user their active permission on the
  # repo.
  #
  # Returns an Array of Teams.
  def active_teams
    @active_teams ||= begin
      active_team_abilities = active_abilities.select { |a| a.actor_type == "Team" }
      Team.where(id: active_team_abilities.map(&:actor_id))
    end
  end

  # Public: Does the user have access to the repo solely through teams (no
  # direct abilities or anything else)?
  def teams_only?
    repository_abilities.sort == team_abilities.sort
  end

  # Public: Get the ids of all the other repos that the user will lose access to
  # if all their permissions on this repo are revoked.
  #
  # Returns an Array of integers.
  def casualty_ids_from_revoking_all
    @casualty_ids_from_revoking_all ||= casualty_ids_from_removing_user_from_teams(user_teams_with_access)
  end

  # Public: Get the ids of all the other repos that the user will lose access to
  # if all their permissions on this repo are revoked.
  #
  # Returns an Array of integers.
  def casualty_ids_from_revoking_active
    @casualty_ids_from_revoking_active ||= casualty_ids_from_removing_user_from_teams(active_teams)
  end

  # Public: Get the active permission that the user will have after calling
  # revoke_active.
  #
  # Returns a symbol (:read, :write, or :admin) or nil if the user will have no
  # access after revoking active.
  def permission_after_revoking_active
    # Filter out inactive_abilities that share an actor_id with an active_abiliity
    # This ensures that we don't return an action from a Team abiltiy that will
    # be removed after revoking the active permission.
    remaining_abilities = inactive_abilities.reject { |ab| active_abilities.map(&:actor_id).include?(ab.actor_id) }

    most_capable_action(remaining_abilities)&.to_sym
  end

  # Public: Is the user an owner of the parent repo's owning organization?
  #
  # Returns a boolean
  def owner_of_parent_org?
    @repo.owner_of_parent_org?(@user)
  end

  private

  def most_capable_action(abilities)
    ability = abilities.sort.last
    ability && ability.action
  end

  # Internal: Get all the abilities that the user has on the repo, keyed by
  # their permission level.
  #
  # Example result:
  #
  # {
  #    :read  => [<ability1>, <ability2>],
  #    :admin => [<ability3>]
  # }
  #
  # Returns a Hash with Symbol keys and Arrays of Abilities as values.
  def abilities_by_permission
    @abilities_by_permission ||= begin
      abilities_hash = { read: [], write: [], admin: [] }

      repository_abilities.each { |ability| abilities_hash[ability.action.to_sym] << ability }

      abilities_hash
    end
  end

  # Internal: Get all the abilities that the user has on the repo.
  #
  # Returns an Array of Abilities.
  def repository_abilities
    @repository_abilities ||= ([direct_ability, organization_ability] + team_abilities).compact
  end

  # Public: Get all the other repos that the user will lose access to if they're
  # removed from the specified teams.
  #
  # teams - Array of Teams that the user could be removed from.
  #
  # Returns an Array of integers.
  def casualty_ids_from_removing_user_from_teams(teams)
    return [] if Ability
                  .user_admin_on_organization(
                    actor_id: @user,
                    subject_id: organization.id).any?
    # All the repos on the teams that the user would be removed from are
    # potential casualties of that removal.
    potential_casualty_ids = teams.map(&:repository_ids).flatten.uniq - [@repo.id]
    return [] if potential_casualty_ids.empty?

    # Get the ids of the teams that the user will still be on after being
    # removed from the specified teams.
    remaining_team_ids = user_team_ids - Set[*teams.map(&:id)]

    sql_bindings = {
      repo_ids: potential_casualty_ids,
      team_ids: remaining_team_ids.to_a,
      user_id: @user.id,
      direct: Ability.priorities[:direct],
    }

    sql = Arel.sql <<-SQL, **sql_bindings
      SELECT subject_id
      FROM   abilities
      WHERE  subject_id   IN (:repo_ids)
      AND    subject_type = 'Repository'
      AND    priority <= :direct
      AND    (
        (actor_id = :user_id AND actor_type = "User")
    SQL

    if remaining_team_ids.present?
      sql += Arel.sql <<-SQL, **sql_bindings
        OR (actor_id IN (:team_ids) AND actor_type = "Team")
      SQL
    end

    sql += Arel.sql(")")

    survivor_ids = Ability.connection.select_values(sql)

    potential_casualty_ids - survivor_ids
  end

  def organization
    @repo.organization
  end

  # Internal: Get all the abilities that the user has on the repo that are
  # through teams. Includes inherited abilities granted based on membership in
  # nested teams.
  #
  # Returns an Array of Abilities.
  def team_abilities
    @team_abilities ||=
      if user_teams_with_access.empty?
        []
      else
        most_capable_team_abilities_for_repository
      end
  end

  # Internal: A convenience wrapper for Ability model objects that allow access
  # to the ability record for which they derive a permission.
  #
  # This allows us to gradually surface the concept of abilities inherited from
  # a nested team ancestor (not yet a first class domain concept) to callers
  # who understand them without breaking legacy callsites (like views, view
  # models and templates), which depend on Ability objects.
  class DerivedAbility < SimpleDelegator
    attr_reader :derived_from

    def initialize(ability, derived_from: nil)
      @derived_from = derived_from
      super ability
    end

    def original_ability
      __getobj__
    end

    def <=>(other)
      original_ability <=> other.original_ability
    end

    def actor_id
      T.bind(self, T.untyped)
      derived_from&.id || super
    end

    def actor
      T.bind(self, T.untyped)
      derived_from.presence || super
    end

    private

    # Internal Ruby Array methods like `flatten` attempt to call the private
    # `to_ary` method on these objects to determine a stop point for recursion.
    #
    # Ruby's Delegate class shows warnings because it does not forward
    # private methods so we simply return nil here to mimic the original
    # `Ability` object:
    #
    # > Ability.new.__send__(:to_ary)
    # => nil
    def to_ary(*)
      nil
    end
  end

  def user_teams
    @user_teams ||= organization.teams_for(@user)
  end

  def user_team_ids
    @user_team_ids ||= Set[*user_teams.map(&:id)]
  end

  # Internal: A list of the most capable abilities for the current repo.
  # Includes abilities inherited from all teams in the user's nested team
  # hierarchy.
  #
  # Returns an Array of Abilities.
  def most_capable_team_abilities_for_repository
    # First we find the most capable direct abilities between the user's
    # organization teams (and ancestor teams).
    #
    # Then we augment those direct abilities with inherited abilities.
    #
    # Finally, we ensure that a team only appears once for each action (:read,
    # :write or :admin):
    team_abilities_for_repository.flat_map { |ability| derived_abilities_for(ability) }
    .group_by(&:action)
    .flat_map { |_, abilities| abilities.uniq(&:actor_id) }
  end

  # Internal: AR relation with all the abilities between teams and repository
  # abilities between teams and repos are always priority :direct
  def team_abilities_for_repository
    Ability.where(
      actor_id: Array(team_and_ancestor_ids_with_access),
      actor_type: "Team",
      subject_id: Array(@repo.id),
      subject_type: "Repository",
      priority: Ability.priorities[:direct],
    )
  end

  # Internal: A list of all derived abilities for the given ability (direct and
  # inherited), based on the user's memberships in user_teams.
  #
  # Returns an Array of DerivedAbility objects (wrappers of Ability).
  def derived_abilities_for(ability)
    user_teams.inject([]) do |abilities, team|
      if direct_ability?(team, ability)
        abilities << DerivedAbility.new(ability)
      elsif inherited_ability?(team, ability)
        abilities << DerivedAbility.new(ability, derived_from: team)
      end
      abilities
    end
  end

  def direct_ability?(team, ability)
    team.id == ability.actor_id
  end

  def inherited_ability?(team, ability)
    team.ancestor_ids.include?(ability.actor_id)
  end

  # Internal: A Set of IDs representing all teams the user has membership on
  # (includes both direct membership and inherited membership via team
  # ancestors).
  #
  # Note: Relies on the tree path field of the Team record to save an expensive
  # query to fetch ancestry.
  #
  # Returns an Array of Integers
  def user_teams_with_ancestor_ids
    @user_teams_with_ancestor_ids ||= user_teams.flat_map(&:id_and_ancestor_ids).uniq
  end

  # Internal: A Set of IDs representing all user teams (direct and inherited)
  # that grant access to the repo.
  #
  # Returns a Set of Integers
  def team_and_ancestor_ids_with_access
    @team_and_ancestor_ids_with_access ||= Set.new(Ability.where(
      actor_type: "Team",
      actor_id: user_teams_with_ancestor_ids,
      subject_id: @repo.id,
      subject_type: "Repository",
      priority: Ability.priorities[:direct],
    ).pluck(:actor_id))
  end
end
