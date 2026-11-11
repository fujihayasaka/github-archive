# typed: true
# frozen_string_literal: true

class Orgs::Settings::DefaultRepositoryPermissionController < ApplicationController
  include OrganizationsHelper
  include OrganizationsControllerMethods

  before_action :login_required
  before_action :org_admins_only
  after_action :customer_category_instrumentation

  def update
    action = params.fetch(:default_repository_permission, "").strip.presence
    settings_context = params.fetch(:settings_context, "").strip.presence

    if current_organization.valid_default_repository_permission?(action)
      begin
        current_organization.update_default_repository_permission(action, actor: current_user)

        if current_organization.custom_roles_supported?
          custom_roles = RepositoryRole.lower_custom_roles(action: action, org: current_organization)
          custom_roles.each { |role| Permissions::CustomRoles.update_users(role, actor: current_user) }
        end

        flash[:notice] = if action != "none"
          "Base repository permission updated to \"#{Configurable::DefaultRepositoryPermission.human_friendly_value(action)}\"."
        else
          "Base repository permission removed."
        end
      rescue Configurable::DefaultRepositoryPermission::AlreadyUpdating
        flash[:error] = "The base repository permission is already being updated."
        return redirect_to :back
      end
    else
      flash[:error] = "You specified an invalid base repository permission."
    end

    if settings_context
      redirect_to("#{settings_org_member_privileges_path(current_organization, enable_tip: params[:enable_tip])}##{settings_context}")
    else
      redirect_to :back
    end
  end
end
