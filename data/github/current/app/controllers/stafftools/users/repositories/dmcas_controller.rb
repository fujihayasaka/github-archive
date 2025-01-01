# typed: true
# frozen_string_literal: true

class Stafftools::Users::Repositories::DmcasController < StafftoolsController
  include Stafftools::Users::ControllerLayoutMethods

  before_action :ensure_user_exists
  before_action :dotcom_required

  layout :content_layout

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    view = Stafftools::User::DmcaReposView.new(user: this_user, page: params[:repo_page], current_user: current_user)
    render "stafftools/users/repositories/dmcas/show", locals: { view: view }
  end
end
