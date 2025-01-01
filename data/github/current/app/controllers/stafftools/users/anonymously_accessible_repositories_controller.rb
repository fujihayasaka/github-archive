# typed: true
# frozen_string_literal: true

class Stafftools::Users::AnonymouslyAccessibleRepositoriesController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists
  before_action :check_anon_access_enabled

  layout :content_layout

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    view = create_view_model(
      Stafftools::User::AnonymousGitAccessReposView,
      user: this_user,
      page: params[:repo_page]
    )

    render "stafftools/users/anonymously_accessible_repositories/index", locals: { view: view }
  end

  private

  def check_anon_access_enabled
    render_404 unless GitHub.anonymous_git_access_enabled?
  end
end
