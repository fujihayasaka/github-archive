# typed: true
# frozen_string_literal: true

class Stafftools::RepositoryWatchersController < StafftoolsController

  before_action :ensure_repo_exists

  layout "layouts/stafftools/repository/collaboration"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    users = Stafftools::Newsies.users_watching_repository(current_repository)
      .order(:login)
      .paginate(page: params[:page] || 1)

    settings = {}
    users.each do |user|
      # I know this is an N+1, but newsies is a mess and fixing this seems like
      # more effort than it is worth since the list is paginated
      settings[user] = Stafftools::NewsiesSettings.new user
    end

    render "stafftools/repository_watchers/index", locals: { users: users, settings: settings }
  end

end
