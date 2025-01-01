# typed: true
# frozen_string_literal: true

class Stafftools::Users::Repositories::ContributionsController < StafftoolsController
  before_action :ensure_user_not_org

  layout "layouts/stafftools/user/collaboration"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    repos_view = Stafftools::User::ReposView.new(user: this_user, page: params[:repo_page])

    render "stafftools/users/repositories/contributions/index", locals: { view: repos_view }
  end
end
