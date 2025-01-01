# typed: true
# frozen_string_literal: true

class Orgs::TeamRepositoriesController < Orgs::Controller
  include Orgs::Teams::TeamRepositories

  layout "team"

  before_action :login_required
  before_action :this_team_required
  before_action :admin_on_team_required, except: [:index, :update]
  before_action :sudo_filter, only: [:create]
  before_action :require_valid_new_permission, only: [:update]
  before_action :require_xhr, only: [:accessible_to_members]
  before_action :set_team_context_crumb, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:accessible_to_members]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:suggestions]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  REPOSITORY_PAGE_SIZE = 30

  def index
    sorted_repo_ids = accessible_team_repository_ids_for_current_user(current_user, this_team, this_organization, query: params[:query])
    paginated_repo_ids = sorted_repo_ids.paginate(page: params[:page], per_page: REPOSITORY_PAGE_SIZE)
    repos_on_current_page = Repository.where(id: paginated_repo_ids)
                                      .sorted_by_name
                                      .includes(:internal_repository, :mirror, :parent, :network)

    override_analytics_location "/orgs/<org-login>/teams/<team-name>/repositories"
    respond_to do |format|
      format.html do
        response.headers["Vary"] = "X-Requested-With"
        if request.xhr?
          render(
            partial: "orgs/team_repositories/list",
            locals: {
              org: this_organization,
              team: this_team,
              repo_count: sorted_repo_ids.count,
              paginated_repo_ids: paginated_repo_ids,
              repos_on_current_page: repos_on_current_page,
              abilities: build_abilities_hash(repositories: repos_on_current_page),
              viewer_can_administer: viewer_can_administer_team?
            })
        else
          render(
            "orgs/team_repositories/index",
            locals: {
              org: this_organization,
              team: this_team,
              repo_count: sorted_repo_ids.count,
              paginated_repo_ids: paginated_repo_ids,
              repos_on_current_page: repos_on_current_page,
              abilities: build_abilities_hash(repositories: repos_on_current_page),
              viewer_can_administer: viewer_can_administer_team?,
              selected_nav_item: :repositories,
              has_all_repo_role: has_all_repo_role?,
            })
        end
      end
    end
  end

  def suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        render partial: "orgs/team_repositories/suggestions", formats: :html, locals: {
          view: create_view_model(Orgs::TeamRepositories::SuggestionsView,
            team: this_team,
            query: params[:q]
          )
        }
      end
    end
  end

  def create
    repo = this_organization.org_repositories.with_name_with_owner(params[:member])

    if repo.nil?
      status = :not_found
    elsif !repo.adminable_by?(current_user)
      status = :unauthorized
    elsif !this_team.has_repository?(repo)
      status = this_team.add_repository(repo, :pull).status
    else
      status = :already_added
    end

    respond_to do |format|
      format.html do
        case status
        when :not_found
          flash[:error] = "The #{params[:member]} repository was not found"
        when :unauthorized
          flash[:error] = "You do not have sufficient permissions to add the #{repo.name} repository to this team"
        when :advisory_workspace
          flash[:error] = "This team must be added to the advisory in order to access the #{repo.name} repository"
        when :success
          flash[:notice] = "The #{repo.name} repository was added to this team"
        when :already_added
          flash[:error] = "The #{repo.name} repository is already added to this team"
        end
        redirect_to team_repositories_path(this_team)
      end
    end
  end

  def update
    return render_404 unless this_organization.direct_member?(current_user)

    repo = this_organization.repositories.find_by_id(params[:repository_id])

    # This endpoint is also used by the settings page of user-owned repositories
    # forked from an organization. In order to support user-owned repositories,
    # we try to find the repository via the current user before we fail.
    #
    # See https://github.com/github/github/issues/83808
    unless repo
      found_repo = current_user.repositories.find_by_id(params[:repository_id])
      if found_repo && found_repo.network_owner == this_organization
        repo = found_repo
      end
    end

    # if it fails to find the repo, it could be that the repo is a forked repo, and the current user is not the owner but actually an org admin.
    # NOTE: the adminable_by (below the next block) will ensure that the current_user is indeed an admin
    repo ||= Repository.where(id: params[:repository_id], organization_id: this_organization.id).where.not(parent_id: nil).first

    return render_404 unless repo && repo.adminable_by?(current_user)
    if request.xhr?
      if this_team.has_repository?(repo)
        this_team.update_repository_permission(repo, params[:permission])
      else
        this_team.add_repository(repo, params[:permission])
      end

      Packages::SyncPackagePermsOnRepoChangeJob.perform_later(repository: repo)

      action = Role.find_role_name!(role_name: params[:permission], repository: repo)
      json = {
        members_with_higher_access: this_team.members_with_higher_access_to?(repo),
        action: action.is_a?(Symbol) ? action.to_s.capitalize : action, # only system roles can be symbols
       }
      render json: json
    else
      inherited_ability = this_team.most_capable_inherited_ability_for_repo(repo)
      inherited_ability_level = Ability.actions[inherited_ability&.action]
      new_ability_level = Ability.actions[new_permission]

      # we clear direct permissions if there is an equal or greater inherited permission
      success = if inherited_ability && inherited_ability_level && new_ability_level && inherited_ability_level >= new_ability_level
        this_team.remove_repository_directly(repo) # Revokes direct ability downstream.
        true # Ability#revoke doesn't return status, so default to return true
      elsif this_team.has_repository?(repo)
        this_team.update_repository_permission(repo, params[:permission]).success?
      else
        this_team.add_repository(repo, params[:permission]).success?
      end

      if !success
        flash[:error] = "There was an error updating this team's permissions"
      elsif this_team.descendants?
        flash[:notice] = "#{this_team.name} and it's child teams now have #{new_permission} permissions to #{repo.name_with_display_owner}"
      else
        flash[:notice] = "#{this_team.name} now has #{new_permission} permissions to #{repo.name_with_display_owner}"
      end

      Packages::SyncPackagePermsOnRepoChangeJob.perform_later(repository: repo)
      redirect_to team_repositories_path(this_team)
    end
  end

  def bulk_remove # rubocop:todo GitHub/UseRestfulActions
    repository_ids = params[:repository_ids]

    repository_ids = repository_ids.map { |id| id.to_i }
    team_repo_ids = this_team.repository_ids.select { |id| repository_ids.include?(id) }
    repos = Repository.where(id: team_repo_ids)

    repos.each do |repository|
      this_team.remove_repository(repository)
    end

    flash[:notice] = "You’ve removed '#{repos.map(&:name_with_display_owner).to_sentence}' from this team."
    redirect_to team_repositories_path(this_team)
  end

  ACCESSIBLE_REPOS_LIMIT = 25

  def accessible_to_members # rubocop:todo GitHub/UseRestfulActions
    roles = this_team.action_or_role_over_repositories(ACCESSIBLE_REPOS_LIMIT)
    @repo_ids = roles.keys
    repositories = Repository.where(id: @repo_ids).owned_by(this_organization).sort_by do
      |r| @repo_ids.index(r.id)
    end

    return render_404 unless this_team.adminable_by?(current_user)

    organization_roles = Array.new
    if this_organization.async_can_read_custom_org_roles?(current_user).sync
      organization_roles = OrganizationRole.assignments_for(actor: this_team, org: this_organization)
    end

    respond_to do |format|
      format.html do
        render partial: "orgs/team_repositories/accessible_to_members", locals: {
          view: create_view_model(Orgs::TeamRepositories::AccessibleToMembersView,
            team: this_team,
            repositories: repositories,
            roles: roles,
            repo_count: accessible_team_repository_ids_for_current_user(current_user, this_team, this_organization).count,
            organization_roles: organization_roles,
            member_name: params[:member],
            action_type: params[:action_type],
            return_to: params[:return_to]
          )
        }
      end
    end
  end

  private

  def require_valid_new_permission
    return if new_permission
    flash[:error] = "A valid permission is required"
    redirect_to team_repositories_path(this_team)
  end

  def new_permission
    repo = this_organization.repositories.find_by_id(params[:repository_id])
    @new_permission ||=
      if repo && Role.valid_custom_role?(params[:permission], org: repo.owner)
        params[:permission]
      else
        Repository.permission_to_action(params[:permission]).to_sym
      end
  rescue ArgumentError
    nil
  end

  def viewer_can_administer_team? # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @viewer_can_administer_team if defined?(@viewer_can_administer_team)
    @viewer_can_administer_team = this_team.adminable_by?(current_user)
  end

  def adminable_repos(repositories)
    return [] unless viewer_can_administer_team?
    GitHub::PrefillAssociations.prefill_batch_method(repositories, :cached_async_adminable_by?, current_user)
    promises = repositories.map do |repo|
      repo.cached_async_adminable_by?(current_user).then do |adminable|
        adminable ? repo.id : nil
      end
    end

    Promise.all(promises).then do |repo_ids|
      repo_ids.compact
    end.sync
  end

  # This returns the most capable ability or repository role that this team has
  # inherited from an ancestor for a repo. If this team has no ancestors, or if its
  # own permissions beat any inherited ones, this resolves with nil.
  # Otherwise, it resolves to a hash that presents a common interface
  # for UserRole and Ability:
  # {
  #   name: "read",         # the string identifier of the permission
  #   level: 0,             # the numeric level of the permission, used for comparison
  #   parent_actor: <Team>, # the ancestor team that granted this permission
  # }
  def async_inherited_action_or_role(repo)
    team = this_team
    return Promise.resolve unless team.ancestor_ids.present?

    promises = [
      Platform::Loaders::MostCapableInheritedTeamRepositoryAbilities.load(team: team, repo: repo),
      Platform::Loaders::Permissions::MostCapableInheritedTeamRepositoryUserRole.load(team: team, repo: repo),
    ]

    Promise.all(promises).then do |ability, user_role|
      if user_role.present? && ability.nil?
        if user_role.role.is_a?(OrganizationRole)
          next {
            name: user_role.role.name,
            level: user_role.role.action_rank,
            is_custom: user_role.role.custom?,
            role_id: user_role.role.id,
            parent_actor: user_role.actor
          }
        end
      end

      next unless ability
      ability_level = Ability::ACTION_RANKING[ability.action.to_sym] || -1
      unless user_role.present?
        next {
          name: ability.action_name,
          level: ability_level,
          parent_actor: ability.actor
        }
      end

      user_role.async_role.then do |role|
        if role.action_rank >= ability_level
          {
            name: role.name,
            level: role.action_rank,
            is_custom: role.custom?,
            role_id: role.id,
            parent_actor: user_role.actor
          }
        else
          {
            name: ability.action_name,
            level: ability_level,
            parent_actor: ability.actor
          }
        end
      end
    end
  end

  # This returns the most capable ability or repository role that this team has
  # on a repo. It resolves to a hash that presents a common interface
  # for UserRole and Ability:
  # {
  #   name: "read",         # the string identifier of the permission
  #   level: 0,             # the numeric level of the permission, used for comparison
  # }
  def async_action_or_role(repository)
    promises = [
      Platform::Loaders::MostCapableTeamRepositoryAbilities.load(team: this_team, repo: repository),
      Platform::Loaders::Permissions::DirectUserRoleOnRepositoryForActor
        .load(actor_id: this_team.id, actor_type: "Team", repo_id: repository.id)
        .then { |user_role| user_role&.async_role }
    ]

    Promise.all(promises).then do |ability, role|
      next unless ability.present?
      ability_rank = Ability::ACTION_RANKING[ability.action.to_sym] || -1

      unless role.present?
        next {
          name: ability.action_name,
          level: ability_rank
        }
      end

      if role.action_rank >= ability_rank
        {
          name: role.name,
          level: role.action_rank,
          is_custom: role.custom?,
          role_id: role.id
        }
      else
        {
          name: ability.action_name,
          level: ability_rank
        }
      end
    end
  end

  # This returns an array of hashes, where each hash represents the permissions data that ought to be
  # displayed for each repository on the page. It includes data on permissions that are inherited from
  # parent teams, if those permissions are greater than those the team has in its own right.
  # Example:
  # { 1 => {                      <- For the repository with id 1
  #   "permission_name": "read",
  #   "permission_level": 0,
  #   "parent_level": -1,         <- This is the level of the inherited permission, if there is one
  #   "inherited": false,
  #   "actor_id": nil,
  #   "adminable_by_current_user": false
  # }}
  #
  # Note: we can't use existing helpers like `team#most_capable_abilities_on_subjects` here because we
  # need to track extra information (e.g. whether the ability is inherited, and from whom)
  def build_abilities_hash(repositories: [])
    return {} if repositories.empty?
    adminable_repos = adminable_repos(repositories)

    most_capable_permission_promises = repositories.map do |repo|
      Promise.all([async_action_or_role(repo), async_inherited_action_or_role(repo)]).then do |direct, inherited|
        most_capable_permission = select_most_capable_permission(direct, inherited)

        {
           repository_id: repo.id,
           permission_name: most_capable_permission[:name],
           permission_level: most_capable_permission[:level],
           parent_level: (inherited && inherited[:level]) || -1,
           inherited: inherited.present?,
           inherited_is_most_capable: inherited.present? && most_capable_permission == inherited,
           parent_name: (inherited && inherited[:parent_actor]&.name) || nil,
           adminable_by_current_user: adminable_repos.include?(repo.id),
           custom: most_capable_permission[:is_custom],
         }
      end
    end

    abilities_hash = {}
    most_capable_permissions = Promise.all(most_capable_permission_promises).sync
    most_capable_permissions.each do |permission|
      abilities_hash[permission[:repository_id]] = permission
    end

    abilities_hash
  end

  def select_most_capable_permission(direct, inherited)
    return direct unless inherited.present?

    # if inherited is present, we know direct is present too (there will be an ability record)
    return direct if direct[:level] > inherited[:level]
    return inherited if inherited[:level] > direct[:level]

    # Use inherited if direct and inherited are the same
    # Doing so provides more information to the user
    return inherited if inherited[:role_id] == direct[:role_id]

    # at least one role is custom - return direct if it is custom, and inherited otherwise
    if direct[:is_custom]
      direct
    else
      inherited
    end
  end

  def has_all_repo_role?
    this_organization.all_repo_role_for_actor("Team", this_team.id_and_ancestor_ids).count > 0
  end
end
