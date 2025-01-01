# typed: true
# frozen_string_literal: true

class Settings::DeletedRepositoriesController < ApplicationController
  include Settings::ControllerMethods

  before_action :login_required
  before_action :dotcom_required

  stylesheet_bundle :settings
  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  def index
    deleted_repos = Repository.owned_by(current_user).network_safe_restoreable.order(deleted_at: :desc).limit(100)

    view = create_view_model(
      Settings::DeletedRepositoriesView,
      target: current_user,
      deleted_repos: deleted_repos,
    )

    render "settings/deleted_repositories/index", locals: { view: view }
  end
end
