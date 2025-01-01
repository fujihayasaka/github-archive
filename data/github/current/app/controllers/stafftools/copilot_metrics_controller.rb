# typed: strict
# frozen_string_literal: true

class Stafftools::CopilotMetricsController < StafftoolsController
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

  sig { void }
  def show
    if this_user.organization?
      copilot_metrics = ::Copilot::Metrics::CopilotMetrics.new(organization: this_user)


      respond_to do |format|
        format.json do
          render json: copilot_metrics.payload, status: 200
        end
        format.html do
          render "stafftools/copilot_metrics/show", locals: {
            details: copilot_metrics.payload,
          }
        end
      end
    else
      redirect_to(stafftools_user_copilot_settings_path(this_user.display_login))
    end
  end
end
