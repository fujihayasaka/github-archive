# typed: true
# frozen_string_literal: true

class Memexes::SettingsController < Memexes::Controller
  include MemexesHelper
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :require_memex_feature_enabled
  before_action :require_this_memex
  before_action :require_org_memex, only: [:update_organization_access, :get_organization_access]
  before_action :user_has_admin_access
  before_action :require_permission, only: [:update_organization_access]

  allow_verified_fetch only: [:update_organization_access]

  attr_reader :actors

  # cluster dependencies analysis will be enabled for this non-get requests
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Memexes::SettingsController#update_organization_access"
  ]

  # global critical dependencies, needed for all actions
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Memex

  depends_on_clusters ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:update_organization_access]

  # updates default permissions for org members
  def update_organization_access # rubocop:todo GitHub/UseRestfulActions
    role_to_grant = params.require(:permission)

    begin
      this_memex.update_organization_wide_role(role_to_grant, current_user)
    rescue ArgumentError
      flash[:error] = "Can't grant permissions"
      return head :bad_request
    end

    head :no_content
  end

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::NotificationsEntries,
    only: [:get_organization_access]

  depends_on_clusters ApplicationRecord::Iam,
    ApplicationRecord::Copilot,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    only: [:get_organization_access],
    optional: true

  def get_organization_access # rubocop:todo GitHub/UseRestfulActions
    render(json: { permission: this_memex.organization_wide_role })
  end

  private

  def require_permission
    return head :bad_request unless params[:permission]
  end

  def require_org_memex
    render_404 unless memex_owner.organization?
  end
end
