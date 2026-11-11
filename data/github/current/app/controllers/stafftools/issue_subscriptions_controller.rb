# typed: true
# frozen_string_literal: true

class Stafftools::IssueSubscriptionsController < StafftoolsController # rubocop:todo GitHub/ControllersShouldHaveTests

  before_action :ensure_repo_exists
  before_action :ensure_issue_exists

  layout "layouts/stafftools/repository/collaboration"

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    optional: false, only: [:index]

  def index
    @watchers = Stafftools::Newsies.subscriptions_for_issue(this_issue)
    @ignorers = Stafftools::Newsies.users_ignoring_issue(this_issue)
    @repo_ignorers =
      Stafftools::Newsies.users_ignoring_repository(current_repository)

    render "stafftools/issue_subscriptions/index"
  end

end
