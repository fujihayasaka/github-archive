# typed: true
# frozen_string_literal: true

class Stafftools::Users::AdministrativeTasksController < StafftoolsController
  include StafftoolsHelper
  include Stafftools::Users::ControllerMethods
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists

  layout :overview_layout

  javascript_bundle :stafftools

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    headers["Cache-Control"] = "no-cache, no-store"
    admin_view = Stafftools::User::AdminView.new(user: this_user)

    render(
      "stafftools/users/administrative_tasks/index",
      locals: {
        view: admin_view,
        spam_flag_timestamp: spam_flag_timestamp(this_user),
      },
    )
  end
end
