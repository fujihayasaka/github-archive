# typed: false
# frozen_string_literal: true

class Orgs::RepoRolesController < Orgs::Controller
  include BaseHelpers::Helpers
  include GitHub::Memoizer
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create, :update]

  READ_REPO_ROLES_ACTIONS = [:repository_roles, :fgps, :fgp_metadata]
  READ_REPO_ROLES_OR_REPO_ADMIN_ACTIONS = [:permission_list]

  before_action :login_required
  before_action :read_repo_roles_or_repo_admin_required, only: READ_REPO_ROLES_OR_REPO_ADMIN_ACTIONS
  before_action :read_repo_roles_required, only: READ_REPO_ROLES_ACTIONS
  before_action :write_repo_roles_required, except: READ_REPO_ROLES_ACTIONS | READ_REPO_ROLES_OR_REPO_ADMIN_ACTIONS
  before_action :ensure_trade_restrictions_allows_org_settings_access

  after_action :emit_update_event, only: [:create, :update, :destroy]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    only: [:edit, :permission_list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Iam,
    only: [:fgps]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Iam,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    ApplicationRecord::Copilot,
    only: [:repository_roles]

  class CustomRolesRoutePayload < ReactPayload::Base
    def route_id
      @role.present? ? "customRepoRolesEditRoute" : "customRepoRolesRoute"
    end

    def initialize(current_organization, role: nil)
      @current_organization = current_organization
      @role = role
    end

    def payload
      base_payload = {
        availablePermissions: {
          Repository: RepoRoleFgps.fgps_payload_for_react(T.must(@current_organization))
        },
        availableBaseRoles: {
          Repository: Role::VALID_REPO_BASE_ROLES
        }
      }

      if @role.present?
        base_payload[:role] = Roles::Types::Role.from_model(@role)
      end

      base_payload
    end
  end

  def repository_roles # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(
      ::Settings::Organization::Roles::IndexView,
      organization: current_organization,
      viewer_permissions: viewer_permissions,
    )
    render "settings/organization/roles/index", locals: { view: view }
  end

  def new
    return render_404 unless current_organization.custom_roles_supported?

    respond_with_react(
      payload: CustomRolesRoutePayload.new(current_organization),
      title: "Repository roles",
      app_name: "custom-roles",
      layout: "layouts/organization_settings",
      page_data: {
        selected_link: :roles,
      },
    )
  end

  def edit
    begin
      role = RepositoryRole.find_by!(id: params[:id], owner_id: current_organization.id, owner_type: current_organization.type)
    rescue ActiveRecord::RecordNotFound
      flash[:error] = "Something went wrong. Could not find the role."
      redirect_to settings_org_repository_roles_path
    else
      respond_with_react(
        payload: CustomRolesRoutePayload.new(current_organization, role: role),
        title: "Edit repository role · #{current_organization.name}",
        app_name: "custom-roles",
        layout: "layouts/organization_settings",
        page_data: {
          selected_link: :roles,
        },
      )
    end
  end

  memoize private def json_payload
    JSON.parse(request.body.read)
  end

  def create
    parsed_params = parse_role_params
    custom_role_params = parsed_params[:custom_role_params]
    fgps = parsed_params[:fgps]

    custom_role = RepositoryRole.new(custom_role_params)
    begin
      Permissions::CustomRoles.create!(custom_role, fgps: fgps)
      GitHub.dogstats.increment("custom_role.created", tags: ["result:success", "owner_type:org", "target_type:repo"])
      flash[:notice] = "#{custom_role.name} role was successfully created" # add flash for redirect after successful creation
      render json: { success: true }, status: :ok
    rescue Role::CustomRoleError => e
      error_message = custom_role.errors.full_messages.to_sentence.presence || "error saving additional permissions"
      Failbot.report!(e, app: "github")
      GitHub.dogstats.increment("custom_role.created", tags: ["result:fail", "owner_type:org", "target_type:repo"])
      render json: { success: false, message: error_message }, status: :unprocessable_entity
    end
  end

  def update
    parsed_params = parse_role_params
    custom_role_params = parsed_params[:custom_role_params]
    fgps = parsed_params[:fgps]

    error_message = nil
    begin
      role = RepositoryRole.find_by!(id: params[:id], owner_id: current_organization.id, owner_type: current_organization.type)
      Permissions::CustomRoles.update!(role, role_params: custom_role_params, fgps: fgps, actor: current_user)
    rescue ActiveRecord::RecordNotFound => e
      error_message = "Something went wrong. Could not update the role at this time."
    rescue Role::CustomRoleError => e
      error_message = role.errors.full_messages.to_sentence.presence || "error saving additional permissions"

      Failbot.report!(e, app: "github")
    end

    if error_message
      GitHub.dogstats.increment("custom_role.updated", tags: ["result:fail", "owner_type:org", "target_type:repo"])
      render json: { success: false, message: error_message }, status: 422
    else
      GitHub.dogstats.increment("custom_role.updated", tags: ["result:success", "owner_type:org", "target_type:repo"])
      flash[:notice] = "#{role.name} role was successfully updated" # add flash for redirect after successful update
      render json: { success: true }, status: :ok
    end
  end

  def destroy
    error_message = nil
    begin
      role = RepositoryRole.find_by!(id: params[:id], owner_id: current_organization.id, owner_type: "Organization")
      Permissions::CustomRoles.destroy!(role, current_user)
    rescue ActiveRecord::ActiveRecordError, ActiveRecord::RecordNotFound
      error_message = "Something went wrong. Could not delete role at this time."
    end

    if error_message
      flash[:error] = error_message
    else
      notice_message =
        if role.custom? && !role&.all_dependencies_updated?
          "#{role.name} role was successfully scheduled for deletion. Check again later."
        else
          "#{role.name} role was successfully deleted"
        end
      flash[:notice] = notice_message
    end
    redirect_to settings_org_repository_roles_path
  end

  # Updates the FGP dropdown and summary with the newly selected base role
  def fgps # rubocop:todo GitHub/UseRestfulActions
    role_name = params.dig(:role, :name)
    role = RepositoryRole.custom_role_by_name(role_name, owner: current_organization) if role_name
    base_role_fgps = RepoRoleFgps.for(base_role: params.dig(:role, :base), owner: current_organization)

    return head 400 if base_role_fgps.nil?

    respond_to do |format|
      format.html do
        render partial: "settings/organization/roles/fgps", locals: {
          view: create_view_model(::Settings::Organization::Roles::NewView,
            organization: current_organization,
            base_role_fgps: base_role_fgps,
            role: role
          )
        }
      end
    end
  end

  # Returns all the FGP metadata associated with a given base role
  def fgp_metadata # rubocop:todo GitHub/UseRestfulActions
    base_role = RepoRoleFgps.for(base_role: params[:base_role], owner: current_organization)
    render json: base_role.available_fgps(current_organization).index_by(&:label)
  end

  # Returns all the FGP metadata associated with a given role
  def permission_list # rubocop:todo GitHub/UseRestfulActions
    role_id = params.dig(:id)

    role = RepositoryRole.find_by(id: role_id)
    return render_404 if role.nil?
    return render_404 unless Role.valid_system_role?(role.name) ||
      (role.custom? && role.owner_id == this_organization.id)

    fgp_metadata = ::RepoFgpMetadata.for_role(role)
    respond_to do |format|
      format.html do
        render partial: "settings/organization/roles/permission_list", locals: {
            permission_list: fgp_metadata,
        }
      end
    end
  end

  private

  # Parse role parameters from JSON request body
  # Returns a hash with parsed parameters
  def parse_role_params
    role_data = json_payload
    base_role_name = role_data["base_role"]&.to_s
    name = role_data["name"]&.to_s&.strip
    description = role_data["description"]&.to_s&.strip
    fgps = role_data["fgps"] || []

    parsed_base_role = base_role_name.present? ? Role.preset_by_name(base_role_name) : nil

    custom_role_params = {
      name: name,
      description: description,
      owner_id: current_organization.id,
      owner_type: current_organization.type,
      base_role_id: parsed_base_role&.id
    }

    {
      custom_role_params: custom_role_params,
      fgps: fgps
    }
  end

  def custom_roles_enabled
    render_404 unless current_organization.custom_roles_supported?
  end

  def emit_update_event
    # destroy does not use JSON
    fgps = if request.content_type&.include?("application/json")
      json_payload["fgps"] || []
    else
      params.dig(:role, :fgps) || []
    end

    GlobalInstrumenter.instrument("roles.custom_role_update", {
      fgps: fgps,
      action: action_name
    })
  end

  def read_repo_roles_required
    if current_organization.nil? || !viewer_permissions[:read]
      render_404
    end
  end

  def write_repo_roles_required
    if current_organization.nil? || !viewer_permissions[:write]
      render_404
    end
  end

  def read_repo_roles_or_repo_admin_required
    return if current_organization && viewer_permissions[:read]

    organization_admin_or_organization_repo_admin_required
  end

  # Returns a Hash of permissions for the current user
  memoize def viewer_permissions
    async_permissions = Promise.all([
      this_organization.async_can_read_custom_repo_roles?(current_user),
      this_organization.async_can_write_custom_repo_roles?(current_user),
      this_organization.async_adminable_by?(current_user)
    ]).then do |read, write, org_admin|
      { read: read, write: write, org_admin: org_admin }
    end
    async_permissions.sync
  end
end
