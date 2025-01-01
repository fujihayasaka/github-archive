# typed: true
# frozen_string_literal: true

class Stafftools::Users::Repositories::StarsController < StafftoolsController
  before_action :ensure_user_not_org

  layout "layouts/stafftools/user/collaboration"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Spokes,
    ApplicationRecord::Pages,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    starred_view = Stafftools::User::StarredReposView.new(user: this_user, page: params[:repo_page])

    render "stafftools/users/repositories/stars/index", locals: { view: starred_view }
  end
end
