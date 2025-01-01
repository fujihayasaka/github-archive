# typed: strict
# frozen_string_literal: true

module GroupSettingsControllerMethods
  extend T::Helpers
  extend ActiveSupport::Concern

  include ReactHelper
  include ApplicationHelper

  MAX_SUGGESTIONS = 20

  requires_ancestor { ApplicationController }

  GroupJson = T.type_alias do
    {
      "id" => T.nilable(Integer),
      "group_path" => String,
      "repositories" => T::Array[{ "id" => Integer, "name" => String }],
      "manageAccessPermissions" => T::Boolean,
      "accessPermissions" => T.nilable(T::Array[{ "id" => Integer, "role" => String }]),
      "allowAdditionalCollaborators" => T.nilable(T::Boolean),
      "manageForkDestination" => T::Boolean,
      "forkDestination" => T.nilable(T::Array[String]), # [EXTERNAL INTERNAL USERS]
    }
  end

  included do
    T.bind(self, T.class_of(ApplicationController))

    # uncomment the below to use react devtools in firefox
    # before_action do
    # SecureHeaders.append_content_security_policy_directives(request, {
    #   script_src: %w('unsafe-inline')
    # })
    # end

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Billing,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Configurations,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories

    depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true
  end

  class_methods do

    sig { returns(String) }
    def react_bundle_name
      "group-settings"
    end
  end

  abstract!

  sig { abstract.returns(Symbol) }
  protected def selected_link; end

  sig { abstract.returns(Organization) }
  protected def group_organization; end

  sig { returns(T::Boolean) }
  protected def read_only?
    true
  end

  sig { overridable.returns(T::Boolean) }
  protected def stafftools?
    false
  end

  sig { overridable.returns(String) }
  protected def layout
    "organization_settings"
  end

  sig { overridable.returns(String) }
  protected def title_prefix
    "Settings · "
  end

  sig { overridable.returns(String) }
  protected def base_path
    organization_group_settings_path
  end

  sig { void }
  def index
    render_react_app(
      payload: index_payload,
      app_payload_generator: -> {
        app_payload
      },
      title: "#{title_prefix}Groups · #{group_organization.display_login}",
      page_data: {
        selected_link:,
      },
      layout:,
      ssr: false
    )
  end

  sig { void }
  def new
    is_root = params[:root] == "true"
    parent_id = params[:parentId] unless is_root
    parent_group = RepositoryGroup.find_by(owner: group_organization, id: parent_id) if parent_id
    render_react_app(
      payload: new_payload(parent_group:, is_root:),
      app_payload_generator: -> {
        app_payload
      },
      title: "#{title_prefix}Groups · #{group_organization.display_login}",
      page_data: {
        selected_link:,
      },
      layout:,
      ssr: false
    )
  end

  sig { void }
  def show
    group_id = params.require(:group_id)
    group = RepositoryGroup.find_by(owner: group_organization, id: group_id)
    return render_404 if group.nil?
    render_react_app(
      payload: show_payload(group:),
      app_payload_generator: -> {
        app_payload
      },
      title: "#{title_prefix}Groups · #{group_organization.display_login}",
      page_data: {
        selected_link:,
      },
      layout:,
      ssr: false
    )
  end

  sig { void }
  def create
    json = JSON.parse(request&.body.read)["group"]

    return render status: 400, json: {
      validation_errors: [{
        field: "group_path",
        message: "Group already exists",
      }]
    } if RepositoryGroup.find_by(owner: group_organization, group_path: json["group_path"]).present?

    group = RepositoryGroup.find_or_create_group(owner: group_organization, group_path: json["group_path"])

    channel, validation_errors, orchestration_failed = update_group(group_json: json, group:)

    if validation_errors.length > 0
      return render status: 400, json: validation_errors
    end

    if orchestration_failed
      return render status: 500, json: {
        message: "Group was created but orchestration failed to start"
      }
    end

    render status: 201, json: {
      channel:,
      id: group.id,
      group_path: json["group_path"],
    }
  end

  sig { void }
  def update
    group_json = T.let(JSON.parse(request&.body.read)["group"], GroupJson)
    group_id = params.require("group_id")

    group = RepositoryGroup.find_by(owner: group_organization, id: group_id)

    return render_404 unless group.present?

    channel, validation_errors, orchestration_failed = update_group(group_json:, group:)

    if validation_errors.length > 0
      return render status: 400, json: {
        validation_errors:,
      }
    end

    if orchestration_failed
      return render status: 500, json: {
        message: "Group was updated but orchestration failed to start"
      }
    end

    render status: 200, json: {
      channel:,
      id: group.id,
      group_path: group_json["group_path"],
    }
  end

  sig { void }
  def delete
    group_id = params.require("group_id")
    group = RepositoryGroup.find_by(owner: group_organization, id: group_id)

    return render_404 unless group.present?

    begin
      group.remove
    rescue ArgumentError => e
      return render status: 400, json: {
        message: e.message
      }
    rescue
      return render status: 500, json: {
        message: "Failed to delete group"
      }
    end

    render status: 200, json: {}
  end

  sig { void }
  def access_permissions_suggestions # rubocop:todo GitHub/UseRestfulActions
    render json: query_teams(query: params[:q])
  end

  sig { void }
  def repository_suggestions # rubocop:todo GitHub/UseRestfulActions
    render json: query_repos(query: params[:q])
  end

  sig { void }
  def group_repositories # rubocop:todo GitHub/UseRestfulActions
    group_id = params.require(:group_id)
    group = RepositoryGroup.find_by(owner: group_organization, id: group_id)
    render_404 unless group.present?
    render json: query_repos(query: params[:q], group:, limit: nil)
  end

  private

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def app_payload
    organization = {
      name: group_organization.display_login
    }
    {
      enabled_features: {},
      maxDepth: 6, # 5 plus the root group
      organization:,
      basePath: base_path,
      readOnly: read_only?,
      isStafftools: stafftools?,
      baseAvatarUrl: GitHub.alambic_avatar_url,
    }
  end

  # all routes will return the list of groups, so they can link back to each other via subgroup path
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def shared_payload
    summary = RepositoryGroup.repository_summary(group_organization)

    groups = summary.map do |key, values|
      {
        "id" => values[:group_id],
        "group_path" => key,
        "direct_count" => values[:direct_count],
        "total_count" => values[:total_count],
        "repos" => values[:repos]
      }
    end

    {
      groups: groups
    }
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def index_payload
    {
      **shared_payload,
    }
  end

  sig { params(parent_group: T.nilable(RepositoryGroup), is_root: T.nilable(T::Boolean)).returns(T::Hash[Symbol, T.untyped]) }
  def new_payload(parent_group:, is_root: false)
    {
      **shared_payload,
      parentGroup: parent_group&.as_json(root: false, only: [
        :id,
        :group_path,
      ]),
      isRoot: is_root,
    }
  end

  sig { params(group: RepositoryGroup).returns(T::Hash[Symbol, T.untyped]) }
  def show_payload(group:)
    access_settings = AccessGroupSetting.load_by_group(group)
    inherited_settings = access_settings&.inherited unless group.group_path == ""
    teams_by_role = access_settings&.value&.[](AccessGroupSetting::TEAMS)
    inherited_teams_by_role = inherited_settings[AccessGroupSetting::TEAMS] if inherited_settings
    team_ids = teams_by_role&.values&.flatten || []
    team_ids += inherited_teams_by_role&.values&.flatten if inherited_teams_by_role
    teams = Team.where(id: team_ids)

    mapped_teams = []
    teams_by_role&.each do |role, ids|
      ids.each do |id|
        mapped_teams.push({
          id:,
          role:,
          name: teams.find_by(id:)&.name || "",
        })
      end
    end

    inherited_mapped_teams = [] unless inherited_teams_by_role.nil?
    inherited_teams_by_role&.each do |role, ids|
      ids.each do |id|
        inherited_mapped_teams&.push({
          id:,
          role:,
          name: teams.find_by(id:)&.name || "",
        })
      end
    end

    orchestration_ids = group.repository_group_settings.filter_map(&:orchestration_id)
    orchestration = SettingOrganizationOrchestration.where(id: orchestration_ids).order(updated_at: :desc).limit(1).first
    orchestration_data = if orchestration
      {
        id: orchestration.id,
        state: orchestration.state,
        succeeded: orchestration.data[:succeeded],
        failed: orchestration.data[:failed],
        total: orchestration.data[:total],
        channel: orchestration.active? ? live_update_view_channel(GitHub::WebSocket::Channels.setting_orchestration_status(orchestration)) : nil,
        completed: orchestration.updated_at
      }
    else
      nil
    end

    inherited_allow_additional_collaborators = !inherited_settings[AccessGroupSetting::DENY]&.include?(AccessGroupSetting::TEAMS) if
      inherited_settings && inherited_settings[AccessGroupSetting::DENY].present?

    access_permissions = {
      teams: mapped_teams,
      allowAdditionalCollaborators: !access_settings.value&.[](AccessGroupSetting::DENY)&.include?(AccessGroupSetting::TEAMS)
    } unless access_settings.nil?

    inherited_access_permissions = {
      teams: inherited_mapped_teams,
      allowAdditionalCollaborators: inherited_allow_additional_collaborators,
    } unless inherited_mapped_teams.nil? && inherited_allow_additional_collaborators.nil?

    fork_settings = ForkGroupSetting.load_by_group(group)
    fork_denials = fork_settings&.value&.[]("deny")
    fork_destinations = {
      internal: true,
      external: true,
      users: true,
    }
    fork_denials&.each do |denial|
      fork_destinations[denial] = false
    end
    {
      **shared_payload,
      group: {
        id: group.id,
        group_path: group.group_path,
        repos: group.repositories.as_json(root: false, only: [:id, :name]),
        directSettings: {
          accessPermissions: access_permissions,
          forkDestinations: fork_destinations,
        },
        inheritedSettings: {
          accessPermissions: inherited_access_permissions,
        },
        orchestration: orchestration_data,
      },
      isRoot: group.group_path == "",
    }
  end

  ### See app/controllers/ruleset_edit_controller_methods.rb, teams_for and repos_for methods

  sig do
    params(query: T.nilable(String), limit: T.nilable(Integer)).returns(T::Array[{
      actorId: Integer,
      actorType: String,
      name: String,
    }])
  end
  def query_teams(query: nil, limit: MAX_SUGGESTIONS)
    teams = T.let([], T::Array[{
      actorId: Integer,
      actorType: String,
      name: String,
    }])
    lower_query = query&.downcase

    group_organization.visible_teams_for(current_user).each do |team|
      next if team.secret?
      team_to_add = {
        actorId: team.id,
        actorType: "Team",
        name: team.name,
      }
      if lower_query.present?
        if team.name.downcase.start_with?(lower_query)
          teams.unshift(team_to_add)
        elsif team.name.downcase.include?(lower_query)
          teams.push(team_to_add)
        end
      else
        teams.push(team_to_add)
      end

      teams = teams.first(limit) unless limit.nil?
    end
    teams
  end

  sig do
    params(query: T.nilable(String), group: T.nilable(RepositoryGroup), limit: T.nilable(Integer))
    .returns(T::Array[T::Hash[Symbol, String]])
  end
  def query_repos(query: nil, group: nil, limit: MAX_SUGGESTIONS)
    matching_repos = []
    scope = Repository.active.includes(:group_map).where(owner: group_organization)
    scope = scope.where(repository_group_maps: { id: nil }) if group.nil?
    scope = scope.where(repository_group_maps: { repository_group_id: group.id }) unless group.nil?

    if query.present?
      exact_match = scope.where("repositories.name = :query", query: query).first

      scope = scope.where("repositories.name like :query", query: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
      if scope.present? && scope.any?
        scope = scope.order("repositories.name")
        scope = scope.limit(limit) unless limit.nil?

        matching_repos = scope.to_a.prepend(exact_match).uniq.compact
      end
    else
      matching_repos = scope.recently_updated.order("repositories.name")
      scope = scope.limit(limit) unless limit.nil?
    end

    matching_repos.map do |repo|
      {
        id: repo.id,
        name: repo.name,
      }
    end
  end

  sig do
    params(group_json: GroupJson, group: RepositoryGroup).returns([String, T::Array[{
      field: T.nilable(String),
      message: String,
    }], T::Boolean])
  end
  def update_group(group_json:, group:)
    settings = []
    validation_errors = []
    orchestration_failed = false
    if group_json["manageForkDestination"]
      # value could be ["EXTERNAL", "INTERNAL", "USERS"]
      value = group_json["forkDestination"]
      fork = ForkGroupSetting.add(group_organization, group.group_path)

      # we need to convert the UI "allow" settings to "deny" settings
      fork.allow_all
      fork.deny_external unless value.include?("EXTERNAL")
      fork.deny_internal unless value.include?("INTERNAL")
      fork.deny_users unless value.include?("USERS")
      fork.save!
      settings << fork
    else
      # delete any existing fork settings here
      fork = ForkGroupSetting.load_by_group(group)
      fork&.destroy!
    end

    if group_json["manageAccessPermissions"]
      value = group_json["accessPermissions"]
      access = AccessGroupSetting.add(group_organization, group.group_path)
      access.reset
      value&.each do |team|
        access.add(team["role"], team["id"])
      end
      if group_json["allowAdditionalCollaborators"]
        access.allow_team_changes
      else
        access.deny_team_changes
      end
      access.save!
      settings << access
    else
      # delete any existing access permission settings here
      access = AccessGroupSetting.load_by_group(group)
      access&.destroy!
    end

    if group.group_path != group_json["group_path"]
      begin
        group.rename(group_json["group_path"])
      rescue ArgumentError => e
        validation_errors << {
          field: "group_path",
          message: e.message,
        }
      end
    end

    current_repos = group.repositories.pluck(:id)
    new_repos = group_json["repositories"].map { |repo| repo["id"] }

    repos_to_add = new_repos - current_repos
    repos_to_remove = current_repos - new_repos

    RepositoryGroupMap.insert_all(repos_to_add.map { |id| { repository_id: id, repository_group_id: group.id } })

    if group.parent_path.nil?
      RepositoryGroupMap.where(repository_id: repos_to_remove, repository_group_id: group.id).destroy_all
    else
      # re-parent all repos in this group to the parent group
      parent = RepositoryGroup.find_by!(owner: group_organization, group_path: group.parent_path)
      group_maps_to_reparent = group.group_maps.where(repository_id: repos_to_remove)
      group_maps_to_reparent.update_all(repository_group_id: parent.id) unless parent.nil?
    end

    channel = if settings.any?
      begin
        orchestration = RepositoryGroupSetting.orchestrate_all(current_user, settings)
        live_update_view_channel(GitHub::WebSocket::Channels.setting_orchestration_status(orchestration))
      rescue ActiveRecord::RecordInvalid => e
        orchestration_failed = true
      end
    end

    [channel, validation_errors, orchestration_failed]
  end
end
