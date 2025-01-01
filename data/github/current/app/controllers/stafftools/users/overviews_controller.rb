# typed: true
# frozen_string_literal: true

class Stafftools::Users::OverviewsController < StafftoolsController
  include Stafftools::Users::ControllerMethods
  include Stafftools::Users::ControllerLayoutMethods

  layout :overview_layout

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    fetch_error_states
    view = Stafftools::User::ShowView.new(user: this_user, current_user: current_user)

    render(
      "stafftools/users/overviews/show",
      locals: {
        view: view,
        error_states: @error_states,
      },
    )
  end
end
