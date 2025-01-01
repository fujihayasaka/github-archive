# typed: true
# frozen_string_literal: true

class Stafftools::CopilotMetricsDashboardsController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  layout :content_layout

  before_action :dotcom_required
  before_action :ensure_user_exists

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:show]

  def show
    if this_user.organization? && user_feature_enabled?(:stafftools_copilot_metrics_dashboards)
      render "stafftools/copilot_metrics_dashboards/show", locals: {}
    else
      redirect_to(stafftools_user_copilot_settings_path(this_user.display_login))
    end
  end
end
