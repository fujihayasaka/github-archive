# typed: true
# frozen_string_literal: true

class Stafftools::Users::SuccessorsController < StafftoolsController
  before_action :ensure_user_not_org
  before_action :dotcom_required

  layout "layouts/stafftools/user/overview"

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
    only: [:index], optional: true

  def index
    latest_invite = SuccessorInvitation.where(inviter: this_user, target: this_user).last

    render(
      "stafftools/users/successors/index",
      locals: { user: this_user, latest_invite: latest_invite },
    )
  end

  private

  def ensure_user_not_org
    return render_404 if this_user.is_a?(Organization)

    ensure_user_exists
  end
end
