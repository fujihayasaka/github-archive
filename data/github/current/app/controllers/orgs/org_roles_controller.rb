# typed: true
# frozen_string_literal: true

class Orgs::OrgRolesController < Orgs::Controller
  include BaseHelpers::Helpers
  include GitHub::Memoizer
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create, :update]
  before_action :login_required
  before_action :read_org_org_roles_required, only: [:index]
  before_action :write_org_org_roles_required, except: [:index]
  before_action :ensure_trade_restrictions_allows_org_settings_access

  after_action :emit_update_event, only: [:create, :update, :destroy]

  stylesheet_bundle :suggestions

  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot, only: [:index, :edit, :new]

  depends_on_clusters ApplicationRecord::Profiles,
    only: [:index]

  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities, only: [:fgp_metadata]

  class CustomRolesRoutePayload < ReactPayload::Base
    def route_id
      @role.present? ? "customOrgRolesEditRoute" : "customOrgRolesRoute"
    end

    def initialize(current_organization:, role: nil)
      @current_organization = current_organization
      @role = role
    end

    def payload
      base_payload = {
        availablePermissions: {
          Organization: OrgRoleFgps.fgps_payload_for_react(T.must(@current_organization)),
          Repository: RepoRoleFgps.fgps_payload_for_react(T.must(@current_organization))
        },
        availableBaseRoles: {
          Repository: OrganizationRole::VALID_BASE_ROLES_FOR_DISPLAY
        }
      }

      if @role.present?
        base_payload[:role] = Roles::Types::Role.from_model(@role)
      end

      base_payload
    end
  end

  def index
    render "settings/organization/org_roles/index", locals: { organization: current_organization, viewer_permissions: viewer_permissions }
  end

  def new
    return render_404 unless current_organization.custom_roles_supported?
    respond_with_react(
      payload: CustomRolesRoutePayload.new(current_organization: current_organization),
      title: "Create a new custom organization role · #{current_organization.name}",
      app_name: "custom-roles",
      layout: "layouts/organization_settings",
      page_data: {
        selected_link: :org_roles,
      },
    )
  end

  def create
    parsed_params = parse_role_params

    custom_role_params = parsed_params[:custom_role_params]
    base_role_name = parsed_params[:base_role_name]
    fgps = parsed_params[:fgps]

    if base_role_name.present?
      unless OrganizationRole::VALID_BASE_ROLES.include?(base_role_name)
        error_message = "Invalid base role"
        return render json: { success: false, message: error_message }, status: 422
      end
      base_role = RepositoryRole.system_repo_roles.find_by(name: base_role_name)
    end

    T.must(custom_role_params)[:base_role_id] = base_role.id if base_role

    custom_role = OrganizationRole.new(custom_role_params)
    error_message = nil
    begin
      Permissions::CustomRoles.create!(custom_role, fgps: fgps)
    rescue Role::CustomRoleError => e
      error_message = custom_role.errors.full_messages.to_sentence.presence || "error saving additional permissions"
      Failbot.report!(e, app: "github")
    end

    if error_message
      GitHub.dogstats.increment("custom_role.created", tags: ["result:fail", "owner_type:org", "target_type:org"])
      render json: { success: false, message: error_message }, status: 422
    else
      GitHub.dogstats.increment("custom_role.created", tags: ["result:success", "owner_type:org", "target_type:org"])
      flash[:notice] = "#{custom_role.name} role was successfully created"
      render json: { success: true }, status: :ok
    end
  end

  def edit
    begin
      role = OrganizationRole.find_by!(id: params[:id], owner_id: current_organization.id, owner_type: current_organization.type)
    rescue ActiveRecord::RecordNotFound
      flash[:error] = "Something went wrong. Could not find the role."
      redirect_to settings_org_roles_path
    else
      assignment_counts = UserRole.where(target_type: "Organization", target_id: current_organization.id, role_id: role.id).group(:actor_type).count
      respond_with_react(
        payload: CustomRolesRoutePayload.new(current_organization: current_organization, role: role),
        title: "Edit custom organization role · #{current_organization.name}",
        app_name: "custom-roles",
        layout: "layouts/organization_settings",
        page_data: {
          selected_link: :org_roles,
        },
      )
    end
  end

  def update
    parsed_params = parse_role_params

    custom_role_params = parsed_params[:custom_role_params]
    base_role_name = parsed_params[:base_role_name]
    fgps = parsed_params[:fgps]

    if base_role_name.blank? || base_role_name == "none"
      custom_role_params[:base_role_id] = nil
    elsif OrganizationRole::VALID_BASE_ROLES.include?(base_role_name)
      custom_role_params[:base_role_id] = RepositoryRole.system_repo_roles.find_by!(name: base_role_name).id
    else
      error_message = "Invalid base role"
      return render json: { success: false, message: error_message }, status: 422
    end

    begin
      role = OrganizationRole.find_by!(id: params[:id], owner_id: current_organization.id, owner_type: current_organization.type)
      Permissions::CustomRoles.update!(role, role_params: custom_role_params, fgps: fgps, actor: current_user)
    rescue ActiveRecord::RecordNotFound => e
      error_message = "Something went wrong. Could not update the role at this time."
    rescue Role::CustomRoleError => e
      error_message = T.must(role).errors.full_messages.to_sentence.presence || "error saving additional permissions"

      Failbot.report!(e, app: "github")
    ensure
      if error_message
        GitHub.dogstats.increment("custom_role.updated", tags: ["result:fail", "owner_type:org", "target_type:org"])
        render json: { success: false, message: error_message }, status: 422
      else
        GitHub.dogstats.increment("custom_role.updated", tags: ["result:success", "owner_type:org", "target_type:org"])
        flash[:notice] = "#{T.must(role).name} role was successfully updated" # add flash for redirect after successful update
        render json: { success: true }, status: :ok
      end
    end
  end

  def destroy
    error_message = nil
    begin
      role = OrganizationRole.find_by!(id: params[:id], owner_id: current_organization.id, owner_type: "Organization")
      Permissions::CustomRoles.destroy!(role, current_user)
    rescue ActiveRecord::ActiveRecordError, ActiveRecord::RecordNotFound
      error_message = "Something went wrong. Could not delete role at this time."
    end

    if error_message
      flash[:error] = error_message
    else
      notice_message =
        if role.custom? && !role.all_dependencies_updated?
          "#{role.name} role was successfully scheduled for deletion. Check again later."
        else
          "#{role.name} role was successfully deleted"
        end
      flash[:notice] = notice_message
    end
    redirect_to settings_org_roles_path
  end

  # Returns all the FGP metadata available for the current organization
  def fgp_metadata # rubocop:todo GitHub/UseRestfulActions
    render json: OrgRoleFgps.for(owner: this_organization).available_fgps(this_organization).index_by(&:label)
  end

  private

  # Internal: This before_action renders a standard 404 page unless
  # `current_user` is capable of reading the org roles for `this_organization`.
  def read_org_org_roles_required
    if current_organization.nil? || !viewer_permissions[:read]
      render_404
    end
  end

  # Internal: This before_action renders a standard 404 page unless
  # `current_user` is capable of writing the org roles for `this_organization`.
  def write_org_org_roles_required
    return if current_user&.site_admin?
    if current_organization.nil? || !viewer_permissions[:write]
      render_404
    end
  end

  def custom_roles_enabled
    render_404 unless current_organization.custom_org_roles_supported?
  end

  # Returns a Hash of permissions for the current user
  memoize def viewer_permissions
    async_permissions = Promise.all([
      this_organization.async_can_read_custom_org_roles?(current_user),
      this_organization.async_can_write_custom_org_roles?(current_user),
    ]).then do |read, write|
      { read: read, write: write }
    end
    async_permissions.sync
  end

  def role_params
    strip_params(:name)

    params.
      require(:role).
      permit(:name, :description, fgps: []).
      merge(owner_id: current_organization.id, owner_type: current_organization.type).
      except(:fgps)
  end

  def strip_params(*keys)
    keys.each { |key| params[:role][key]&.strip! }
  end

  def emit_update_event
    GlobalInstrumenter.instrument("org_roles.custom_role_update", {
      fgps: params.dig(:role, :fgps) || [],
      action: params.dig(:action)
    })
  end

  # Parse role parameters from a JSON request body.
  # Returns a hash with :custom_role_params, :base_role_name, and :fgps keys.
  def parse_role_params
    # Check if this is a React-enabled request with JSON body
    role_data = JSON.parse(request.body.read)
    base_role_name = role_data.key?("base_role") ? role_data["base_role"].to_s : ""
    name = role_data["name"].to_s.strip
    description = role_data["description"].to_s.strip
    fgps = role_data["fgps"] || []
    owner_id = current_organization.id
    owner_type = current_organization.type

    custom_role_params = { name: name, description: description, owner_id: owner_id, owner_type: owner_type }

    {
      custom_role_params: custom_role_params,
      base_role_name: base_role_name,
      fgps: fgps
    }
  end
end
