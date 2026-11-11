# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/ControllersShouldHaveTests
class Stafftools::Users::MeteredExportsController < StafftoolsController
  # rubocop:enable GitHub/ControllersShouldHaveTests
  include Stafftools::Users::ControllerLayoutMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:show]

  layout :billing_layout
  before_action :ensure_user_exists

  def index
    render "stafftools/users/metered_exports/index", locals: {
      metered_exports: this_user.metered_usage_exports.preload(:requester).order(created_at: :desc)
    }
  end

  def show
    export = this_user.metered_usage_exports.find(params[:id])

    redirect_to export.generate_expiring_url
  end
end
