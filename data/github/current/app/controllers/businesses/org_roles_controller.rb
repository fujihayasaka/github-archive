# typed: true
# frozen_string_literal: true

class Businesses::OrgRolesController < Businesses::BusinessController
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
    only: [:index, :new]

  def index
    render "businesses/org_roles/index", locals: { business: this_business, viewer_permissions: viewer_permissions }
  end

  def new
    render "businesses/org_roles/new", locals: { business: this_business }
  end

  def edit
    role = OrganizationRole.find_by!(id: params[:id], owner_id: this_business.id, owner_type: "Business")
    assignment_counts = UserRole.where(target_type: "Organization", target_id: this_business.organizations.ids, role_id: role.id).group(:actor_type).count
    render "businesses/org_roles/edit", locals: { business: this_business, role: role, assignment_counts: assignment_counts }
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Something went wrong. Could not find the role."
    redirect_to enterprise_organization_roles_path(this_business)
  end

  def create
    base_role_name = params[:role].delete(:base_role)
    base_role = nil

    if base_role_name.present?
      unless OrganizationRole::VALID_BASE_ROLES.include?(base_role_name)
        flash[:error] = "Invalid base role"
        redirect_to enterprise_new_organization_role_path(this_business)
        return
      end
      base_role = RepositoryRole.system_repo_roles.find_by(name: base_role_name)
    end
    custom_role_params = role_params
    custom_role_params[:base_role_id] = base_role.id if base_role

    custom_role = OrganizationRole.new(custom_role_params)
    error_message = nil
    begin
      Permissions::CustomRoles.create!(custom_role, fgps: params.dig(:role, :fgps))
    rescue Role::CustomRoleError => e
      error_message = custom_role.errors.full_messages.to_sentence.presence || "error saving additional permissions"
      Failbot.report!(e, app: "github")
    end

    if error_message
      GitHub.dogstats.increment("custom_role.created", tags: ["result:fail", "owner_type:business", "target_type:org"])
      flash[:error] = error_message
      redirect_to enterprise_new_organization_role_path(this_business)
    else
      GitHub.dogstats.increment("custom_role.created", tags: ["result:success", "owner_type:business", "target_type:org"])
      flash[:notice] = "#{custom_role.name} role was successfully created"
      redirect_to enterprise_organization_roles_path(this_business)
    end
  end

  def update
    base_role_name = params[:role].delete(:base_role)
    custom_role_params = role_params

    if base_role_name.blank? || base_role_name == "none"
      custom_role_params[:base_role_id] = nil
    elsif OrganizationRole::VALID_BASE_ROLES.include?(base_role_name)
      custom_role_params[:base_role_id] = RepositoryRole.system_repo_roles.find_by!(name: base_role_name).id
    else
      flash[:error] = "Invalid base role"
      return redirect_to enterprise_edit_organization_role_path(this_business)
    end

    begin
      role = OrganizationRole.find_by!(id: params[:id], owner_id: this_business.id, owner_type: "Business")
      new_fgps = params[:role].delete(:fgps) || []
      Permissions::CustomRoles.update!(role, role_params: custom_role_params, fgps: new_fgps, actor: current_user)
    rescue ActiveRecord::RecordNotFound => e
      error_message = "Something went wrong. Could not update the role at this time."
    rescue Role::CustomRoleError => e
      error_message = T.must(role).errors.full_messages.to_sentence.presence || "error saving additional permissions"

      Failbot.report!(e, app: "github")
    ensure
      if error_message
        GitHub.dogstats.increment("custom_role.updated", tags: ["result:fail", "owner_type:business", "target_type:org"])
        flash[:error] = error_message
        redirect_to enterprise_edit_organization_role_path(this_business)
      else
        GitHub.dogstats.increment("custom_role.updated", tags: ["result:success", "owner_type:business", "target_type:org"])
        flash[:notice] = "#{T.must(role).name} role was successfully updated"
        redirect_to enterprise_organization_roles_path(this_business)
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
