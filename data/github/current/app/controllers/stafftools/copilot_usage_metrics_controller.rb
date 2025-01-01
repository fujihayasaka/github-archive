# typed: true
# frozen_string_literal: true

class Stafftools::CopilotUsageMetricsController < StafftoolsController
  layout "layouts/stafftools/user/content"

  before_action :dotcom_required
  before_action :ensure_user_exists

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  def show
    if this_user.organization?
      usage_metrics = ::Copilot::Metrics::UsageMetrics.new(organization: this_user)
      respond_to do |format|
        format.json do
          render json: usage_metrics.usage_details, status: 200
        end
        format.html do
          render "stafftools/copilot_usage_metrics/show", locals: {
            copilot_organization: Copilot::Organization.new(this_user),
            details: usage_metrics.usage_details,
          }
        end
      end
    else
      redirect_to(stafftools_user_copilot_settings_path(this_user.display_login))
    end
  end
end
