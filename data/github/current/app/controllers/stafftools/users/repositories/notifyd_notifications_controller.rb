# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true
class Stafftools::Users::Repositories::NotifydNotificationsController < StafftoolsController
  before_action :ensure_user_not_org
  before_action :dotcom_required

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
    notifyd_view = Stafftools::User::NotifydView.new(user: this_user)
    render(
      "stafftools/users/repositories/notification_preferences/notifyd",
      locals: { view: notifyd_view },
    )
  end
end
