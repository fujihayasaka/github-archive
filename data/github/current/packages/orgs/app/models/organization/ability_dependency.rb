# typed: true
# frozen_string_literal: true

module Organization::AbilityDependency
  extend ActiveSupport::Concern

  include Ability::Actor
  include Ability::Subject
  include Ability::Membership

  extend T::Helpers

  requires_ancestor { Organization }

  DEPENDENT_UPDATE_LIMIT = Ability::BATCH_SIZE

  # Thrown when someone tries to do something with a non-member of an org when
  # org membership is required.
  class DirectMemberRequiredError < StandardError
    def initialize(organization, user)
      super "#{user.login} isn't a direct member of the #{organization.login} org"
    end
  end

  def permit?(actor, action)
    async_permit?(actor, action).sync
  end

  def async_permit?(actor, action)
    actor = actor.ability_delegate

    return Promise.resolve(false) if !actor.is_a?(User) || actor.new_record?

    super
  end

  # Public: Check if the given user is either an owner or billing manager of this organization.
  #
  # user - a User
  #
  # Returns a Boolean.
  def billing_manageable_by?(user)
    adminable_by?(user) || billing_manager?(user)
  end

  # Public: Check if the given user is either an owner or billing manager of this organization.
  #
  # user - a User
  #
  # Returns a Promise that resolves to a Boolean.
  def async_billing_manageable_by?(user)
    async_adminable_by?(user).then do |is_admin|
      next true if is_admin
      async_billing_manager?(user)
    end
  end

  # Public: Is this user *only* a billing manager
  # of the organization, having no further
  # relations with the organization?
  #
  # Returns a Boolean.
  def billing_manager_only?(user)
    !direct_or_team_member?(user) && billing_manager?(user)
  end

  def current_or_pending_billing_manager?(user)
    billing_manager?(user) || pending_invitation_for(user)&.role == "billing_manager"
  end

  def dependents
    dependent_repos = Repository.owned_by_org(self).select(:id).all
    dependent_teams = teams.select(:id).all
    dependent_projects = projects.select(:id).all

    dependent_repos + dependent_teams + dependent_projects
  end

  # Internal: A hash of dependent types and corresponding ids
  # Used by Ability::Grant#update as an alternative to #dependents to increase
  # performance for organizations with many repositories
  def dependent_ids_by_type
    {
      "Team" => teams.pluck(:id),
      "Repository" => Repository.owned_by_org(self).pluck(:id),
      "Project" => projects.pluck(:id),
    }
  end

  # Public: The number of dependents owned by this organization
  def dependents_count
    dependent_ids_by_type.reduce(0) do |count, (_, ids)|
      count = count + ids.size
      count
    end
  end

  # Public: The number of dependents that can safely be updated within a
  # request/response timeout limit
  def dependent_update_limit
    DEPENDENT_UPDATE_LIMIT
  end

  def dependents?
    true
  end

  def dependent_added(dependent)
    super

    return unless dependent.is_a?(Repository)
    return if default_repository_permission == :none

    dependent.add_organization(self, action: default_repository_permission)
  end

  def dependent_removed(dependent)
    super

    return unless dependent.is_a?(Repository)

    dependent.remove_organization(self)
    dependent.remove_inaccessible_forks_for(admins.map(&:id))
  end

  # Public: direct admin members of this organization
  def direct_admins(actor_ids: nil, limit: nil)
    members(action: :admin, actor_ids: actor_ids, limit: limit)
  end

  # Public: ids of the direct admins of this organization
  def direct_admin_ids(actor_ids: nil, limit: nil)
    member_ids(action: :admin, actor_ids: actor_ids, limit: limit)
  end

  # Public: direct members of this organization
  def direct_members
    members
  end

  # Public: ids of the direct members of this organization
  def direct_member_ids
    member_ids
  end

  # Public: Is user a direct member of the Organization?
  def direct_member?(user)
    member?(user)
  end

  # Public: Get all direct abilities for a user in an organization.
  def user_direct_abilities_for_organization_teams_and_repositories(user)
    repo_ids = Repository.where(organization_id: id).pluck(:id)
    team_ids = Team.where(organization_id: id).pluck(:id)

    abilities = Ability.where(actor_type: "User",
                              actor_id: user.id,
                              subject_type: "Organization",
                              subject_id: id,
                              priority: 1).to_a

    team_ids.each_slice(1000) do |ids|
      abilities.concat Ability.where(actor_type: "User",
                                     actor_id: user.id,
                                     subject_type: "Team",
                                     subject_id: ids,
                                     priority: 1).to_a
    end

    repo_ids.each_slice(1000) do |ids|
      abilities.concat Ability.where(actor_type: "User",
                                   actor_id: user.id,
                                   subject_type: "Repository",
                                   subject_id: ids,
                                   priority: 1).to_a
    end

    abilities
  end

  # Public: Get all repo access for a user in an organization.
  # returns a hash of actor_type => [actor_id]
  def user_all_repo_role_access(user)
    user_roles = all_repo_role_for_actor("User", user.id)
    all_team_ids = Set.new
    owner.teams_for(user).each { |team| all_team_ids.merge(team.id_and_ancestor_ids) }
    team_roles = all_repo_role_for_actor("Team", all_team_ids)
    user_roles.merge(team_roles)
  end

  def all_repo_role_for_actor(actor_type, actor_ids)
    actor_ids = Array(actor_ids)
    return {} if actor_ids.empty?

    params = {
      actor_type: actor_type,
      target_id: self.id,
      actor_ids: actor_ids.to_a
    }

    user_role_sql = Arel.sql(<<~SQL, **params)
      SELECT DISTINCT ur.actor_id, ur.actor_type
      FROM user_roles ur
      INNER JOIN roles r ON ur.role_id = r.id
      INNER JOIN role_permissions rp on rp.role_id = r.base_role_id
      WHERE ur.actor_type = :actor_type
      AND ur.actor_id IN (:actor_ids)
      AND ur.target_type = 'Organization'
      AND ur.target_id = :target_id
      AND rp.action in ('read_repo', 'write_repo', 'admin_repo')
    SQL

    results = UserRole.connection.select_rows(user_role_sql)

    mapped_results = results.each_with_object({}) do |(actor_id, actor_type), map|
      map[actor_type] ||= []
      map[actor_type] << actor_id
    end

    mapped_results
  end

  def highest_all_repo_access_by_actor_type
    start_time = GitHub::Dogstats.monotonic_time
    params = {
      target_id: self.id,
    }

    user_role_sql = Arel.sql(<<~SQL, **params)
      SELECT DISTINCT ur.actor_id, ur.actor_type, rp.action, r.id, r.name
      FROM user_roles ur
      INNER JOIN roles r ON ur.role_id = r.id
      INNER JOIN role_permissions rp on rp.role_id = r.base_role_id
      WHERE ur.target_type = 'Organization'
      AND ur.target_id = :target_id
      AND rp.action in ('read_repo', 'write_repo', 'admin_repo')
      ORDER BY ur.actor_id
      LIMIT 1000
    SQL

    results = UserRole.connection.select_rows(user_role_sql)

    # an actor can have multiple roles, only keep the highest level one.
    highest_access = results.each_with_object({}) do |(actor_id, actor_type, action, role_id, role_name), map|
      ability = Ability::ALL_REPO_ROLE_FGP_ABILITY[action]
      map[actor_type] ||= {}
      map[actor_type][actor_id] ||= { ability: nil, role_ids: [], role_name: nil }
      if !map[actor_type][actor_id][:ability] || Ability::ACTION_RANKING[ability] > Ability::ACTION_RANKING[map[actor_type][actor_id][:ability]]
        map[actor_type][actor_id][:ability] = ability
        map[actor_type][actor_id][:role_name] = role_name
      end
      map[actor_type][actor_id][:role_ids] << role_id
    end

    user_ids = highest_access["User"]&.keys || []
    team_ids = highest_access["Team"]&.keys || []

    users = fetch_users(user_ids)
    teams = fetch_teams(team_ids)

    # Create a hash with user and team objects including access levels
    hydrated_access = {
      "User" => users.map do |user|
        user_data = highest_access["User"][user.id]
        {
          user: user,
          access_level: user_data[:ability],
          role_ids: user_data[:role_ids].uniq,
          role_name: user_data[:role_name],
        }
      end,
      "Team" => teams.map do |team|
        team_data = highest_access["Team"][team.id]
        {
          team: team,
          access_level: team_data[:ability],
          role_ids: team_data[:role_ids].uniq,
          role_name: team_data[:role_name],
        }
      end
    }

    tags = {
      organization_id: self.id,
      assignments_count: (highest_access.size / 100.0).ceil * 100, # Round up to the next 100
    }.map { |k, v| "#{k}:#{v}" }

    GitHub.dogstats.distribution_timing_since("organization_wide_access_fetch_size.dist", start_time, tags: tags)

    hydrated_access
  end

  def fetch_users(user_ids)
    User.batched_scope(:id, values: user_ids.uniq).to_a
  end

  def fetch_teams(team_ids)
    Team.batched_scope(:id, values: team_ids.uniq).to_a
  end

  # Internal: Organizations are actors and subjects.
  def connector?
    true
  end

  # Internal: Only users can directly act on organizations.
  def grant?(actor, action)
    actor.is_a?(User) && actor.user?
  end

  # Fetch all of the custom roles for the organization
  def custom_roles
    # todo - remove after verifying this is not called.
    GitHub.dogstats.increment("packages.orgs.app.models.organization.ability_dependency.custom_roles")
    ::Role.custom_roles_for_org(self)
  end

  def all_custom_roles
    ::Role.custom_roles_for_org(self)
  end

  def custom_org_roles
    ::OrganizationRole.custom_roles_for_org(self)
  end

  def custom_repo_roles
    ::RepositoryRole.custom_roles_for_org(self)
  end
end
