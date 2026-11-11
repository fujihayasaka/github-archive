# typed: true
# frozen_string_literal: true

class Stafftools::Users::Repositories::ContributionsController < StafftoolsController
  before_action :ensure_user_not_org

  layout "layouts/stafftools/user/collaboration"

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Stafftools::Users::Repositories::ContributionsController#destroy",
  ]

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
    ApplicationRecord::Profiles,
    only: [:index, :destroy]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :destroy], optional: true

  def index
    repos_view = Stafftools::User::ReposView.new(user: this_user, page: params[:repo_page])

    render "stafftools/users/repositories/contributions/index", locals: { view: repos_view }
  end

  def destroy
    UserRankedRepositories.clear_cache(this_user)
    redirect_to stafftools_user_repositories_contributions_path(this_user)
  end
end
