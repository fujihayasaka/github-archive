# typed: true
# frozen_string_literal: true

class Stafftools::Users::RepositoriesController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists

  layout :content_layout

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::Billing,
    ApplicationRecord::Pages,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    repos_view = Stafftools::User::ReposView.new(user: this_user, page: params[:repo_page])
    private_forks_view = Stafftools::User::PrivateForksView.new(
      user: this_user,
      page: params[:repo_page],
    )

    render(
      "stafftools/users/repositories/index",
      locals: { view: repos_view, private_forks_view: private_forks_view },
    )
  end
end
