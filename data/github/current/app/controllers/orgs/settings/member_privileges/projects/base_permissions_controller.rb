# typed: true
# frozen_string_literal: true

class Orgs::Settings::MemberPrivileges::Projects::BasePermissionsController < Orgs::Controller
  before_action :organization_admin_required

  PROJECT_ROLES = {
    "project_reader" => "read",
    "project_writer" => "write",
    "project_admin" => "admin",
    "none" => "none",
  }.freeze

  def update
    return render_error unless valid_parameter?
    role = params[:org_projects_permission_role]

    begin
      current_organization.update_organization_wide_projects_role(role, current_user)
    rescue ArgumentError
      flash[:error] = "Can't update permissions"
      return redirect_to :back
    end

    publish_memex_event(role)
    redirect_to :back, notice: "Base permission updated to \"#{PROJECT_ROLES[role].titlecase}\" for projects."
  end

  private

  def valid_parameter?
    PROJECT_ROLES.key?(params[:org_projects_permission_role])
  end

  def render_error
    flash[:error] = "You specified an invalid value for the 'projects base permission role' setting."
    redirect_to :back
  end

  def publish_memex_event(role)
    GlobalInstrumenter.instrument("memex_event",
      {
        actor: current_user,
        memex_project: nil,
        memex_project_column: nil,
        memex_project_item: nil,
        memex_project_view: nil,
        name: "org_update_base_permission_role",
        ui: nil,
        context: {
          role: role,
          org_id: current_organization.id,
        }.to_json,
      }
    )
  end
end
