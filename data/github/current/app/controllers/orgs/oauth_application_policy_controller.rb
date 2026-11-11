# typed: true
# frozen_string_literal: true

class Orgs::OauthApplicationPolicyController < Orgs::Controller
  before_action :organization_admin_required, only: :update
  before_action :manage_org_oauth_policy_permission_required
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :sudo_filter

  javascript_bundle :settings

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:show]

  preload_features [:first_party_oauth_app_restrictions]

  def show
    requests = this_organization.oauth_application_approvals

    @pending_requests  = requests.pending_approval
    @approved_requests = requests.approved
    @denied_requests   = requests.denied

    if this_organization.first_party_oauth_app_restrictions_enabled?
      @blocked_client_apps = requests.blocked.map(&:application)
      @unblocked_client_apps = OauthApplication.blockable_client_apps - @blocked_client_apps
    end

    render "orgs/oauth_application_policy/show"
  end

  def update
    if restrict_access = params[:restrict_access].presence
      if restrict_access == "on"
        this_organization.enable_oauth_application_restrictions
      else
        this_organization.disable_oauth_application_restrictions
      end
    end

    if request.xhr?
      head :ok
    else
      redirect_to settings_org_oauth_application_policy_path(this_organization)
    end
  end

  def splash # rubocop:todo GitHub/UseRestfulActions
    render "orgs/oauth_application_policy/splash"
  end
end
