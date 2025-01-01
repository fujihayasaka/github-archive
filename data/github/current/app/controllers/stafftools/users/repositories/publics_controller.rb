# typed: true
# frozen_string_literal: true

class Stafftools::Users::Repositories::PublicsController < StafftoolsController
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
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    view = Stafftools::User::PublicReposView.new(user: this_user, page: params[:repo_page])
    render "stafftools/users/repositories/publics/show", locals: { view: view }
  end
end
