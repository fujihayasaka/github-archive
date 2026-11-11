# typed: true
# frozen_string_literal: true

class Orgs::InsightsController < Orgs::Controller
  before_action :login_required
  before_action :organization_insights_required

  layout "orgs/insights/layouts/insights_container"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  FLAGS = [
    :policies,
  ]

  def index
    if copilot_metrics_permission_check.copilot_insights_org_dashboard_accessible?
      return redirect_to copilot_insights_usage_path(this_organization)
    end

    if this_organization.actions_usage_metrics_enabled?(current_user)
      return redirect_to actions_usage_metrics_path(this_organization)
    end

    if this_organization.dependency_insights_visible?(current_user)
      return redirect_to packages_dashboard_org_insights_path
    end

    if this_organization.api_insights_enabled?(current_user)
      return redirect_to api_org_insights_path(this_organization)
    end

    render_404
  end
end
