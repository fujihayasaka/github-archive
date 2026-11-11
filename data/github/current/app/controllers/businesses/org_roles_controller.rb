# typed: true
# frozen_string_literal: true

class Businesses::OrgRolesController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:create, :update]
  #before_action :business_user_account_required
  before_action :enterprise_custom_org_roles_feature_enabled

  before_action :read_enterprise_org_roles_required, only: [:index]
  before_action :write_enterprise_org_roles_required, except: [:index]

  # after_action :emit_update_event, only: [:create, :update, :destroy]


  depends_on_clusters \
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    only: [:index, :new, :edit]

  class CustomRolesRoutePayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      @role.present? ? "customEnterpriseOwnedOrgRolesEditRoute" : "customEnterpriseOwnedOrgRolesRoute"
    end
    sig { params(this_business: Business, role: T.nilable(OrganizationRole)).void }
    def initialize(this_business, role: nil)
      @this_business = this_business
      @role = role
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      base_payload = {
        owner_type: "Enterprise",
        owner_id: T.let(@this_business, Business).id,
        owner_name: T.let(@this_business, Business).name,
        availablePermissions: {
          Organization: OrgRoleFgps.fgps_payload_for_react(@this_business),
          Repository: RepoRoleFgps.fgps_payload_for_react(@this_business),
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
    render "businesses/org_roles/index", locals: { business: this_business, viewer_permissions: viewer_permissions }
  end

  def new
    respond_with_react(
      payload: CustomRolesRoutePayload.new(this_business),
      title: "Create a new custom enterprise owned org role · #{this_business.name}",
      app_name: "custom-roles",
      page_data: {
        sidebar: :people,
        selected_link: :business_organization_roles,
      },
      layout: "layouts/react_business"
    )
  end

  def edit
    role = OrganizationRole.find_by!(id: params[:id], owner_id: this_business.id, owner_type: "Business")
    assignment_counts = UserRole.where(target_type: "Organization", target_id: this_business.organizations.ids, role_id: role.id).group(:actor_type).count

    respond_with_react(
      payload: CustomRolesRoutePayload.new(this_business, role: role),
      title: "Edit custom enterprise owned org role · #{this_business.name}",
      app_name: "custom-roles",
      page_data: {
        sidebar: :people,
        selected_link: :business_organization_roles,
      },
      layout: "layouts/react_business"
    )
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Something went wrong. Could not find the role."
    redirect_to enterprise_organization_roles_path(this_business)
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

    custom_role_params[:base_role_id] = base_role.id if base_role

    custom_role = OrganizationRole.new(custom_role_params)
    error_message = nil
    begin
      Permissions::CustomRoles.create!(custom_role, fgps: fgps)
    rescue Role::CustomRoleError => e
      error_message = custom_role.errors.full_messages.to_sentence.presence || "error saving additional permissions"
      Failbot.report!(e, app: "github")
    end

    if error_message
      GitHub.dogstats.increment("custom_role.created", tags: ["result:fail", "owner_type:business", "target_type:org"])
      render json: { success: false, message: error_message }, status: 422
    else
      GitHub.dogstats.increment("custom_role.created", tags: ["result:success", "owner_type:business", "target_type:org"])
      flash[:notice] = "#{custom_role.name} role was successfully created"
      render json: { success: true }, status: :ok
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
      role = OrganizationRole.find_by!(id: params[:id], owner_id: this_business.id, owner_type: "Business")
      Permissions::CustomRoles.update!(role, role_params: custom_role_params, fgps: fgps, actor: current_user)
    rescue ActiveRecord::RecordNotFound => e
      error_message = "Something went wrong. Could not update the role at this time."
    rescue Role::CustomRoleError => e
      error_message = T.must(role).errors.full_messages.to_sentence.presence || "error saving additional permissions"

      Failbot.report!(e, app: "github")
    ensure
      if error_message
        GitHub.dogstats.increment("custom_role.updated", tags: ["result:fail", "owner_type:business", "target_type:org"])

        render json: { success: false, message: error_message }, status: 422
      else
        GitHub.dogstats.increment("custom_role.updated", tags: ["result:success", "owner_type:business", "target_type:org"])
        flash[:notice] = "#{T.must(role).name} role was successfully updated" # add flash for redirect after successful update

        render json: { success: true }, status: :ok
      end
    end
  end

  def destroy
    error_message = nil
    begin
      role = OrganizationRole.find_by!(id: params[:id], owner_id: this_business.id, owner_type: "Business")
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
    redirect_to enterprise_organization_roles_path
  end

  def org_roles_fgp_metadata # rubocop:todo GitHub/UseRestfulActions
    render json: OrgRoleFgps.new.available_fgps(this_business).index_by(&:label)
  end

  def repo_roles_fgp_metadata # rubocop:todo GitHub/UseRestfulActions
    render json: RepoRoleFgps.fgps_payload(this_business)
  end

  private

  # Parse role parameters from the JSON request body
  # Returns a hash with parsed parameters
  memoize def parse_role_params
    role_data = JSON.parse(request.body.read)
    base_role_name = role_data.key?("base_role") ? role_data["base_role"].to_s : ""
    name = role_data["name"].to_s.strip
    description = role_data["description"].to_s.strip
    fgps = role_data["fgps"] || []
    owner_id = this_business.id
    owner_type = "Business"

    custom_role_params = { name: name, description: description, owner_id: owner_id, owner_type: owner_type }

    {
      custom_role_params: custom_role_params,
      base_role_name: base_role_name,
      fgps: fgps
    }
  end

  sig { void }
  def enterprise_custom_org_roles_feature_enabled
    render_404 unless this_business&.custom_organization_roles_supported?
  end

  sig { void }
  def read_enterprise_org_roles_required
    render_404 unless viewer_permissions[:read]
  end

  sig { void }
  def write_enterprise_org_roles_required
    render_404 unless viewer_permissions[:write]
  end

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  memoize def viewer_permissions
    permissions = Authz.domain.check_multiple_permissions(
      current_user,
      [:read_enterprise_custom_org_role, :write_enterprise_custom_org_role],
      this_business,
    )
    {
      read: permissions[:read_enterprise_custom_org_role],
      write: permissions[:write_enterprise_custom_org_role],
    }
  end

  def role_params
    strip_params(:name)

    params.
      require(:role).
      permit(:name, :description, fgps: []).
      merge(owner_id: this_business.id, owner_type: "Business").
      except(:fgps)
  end

  def strip_params(*keys)
    keys.each { |key| params[:role][key]&.strip! }
  end
end
