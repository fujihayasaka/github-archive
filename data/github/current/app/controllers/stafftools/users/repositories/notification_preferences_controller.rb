# typed: true
# frozen_string_literal: true

class Stafftools::Users::Repositories::NotificationPreferencesController < StafftoolsController
  before_action :ensure_user_not_org

  layout "layouts/stafftools/user/collaboration"

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
    watching_view = Stafftools::User::WatchingView.new(user: this_user)

    render(
      "stafftools/users/repositories/notification_preferences/index",
      locals: { view: watching_view },
    )
  end

  def destroy
    repo = Repositories::Public.find_active!(params[:repository_id])
    this_user.unwatch_repo(repo)

    if request.xhr?
      head :ok
    else
      redirect_to stafftools_user_repositories_notification_preferences_path(this_user)
    end
  end
end
