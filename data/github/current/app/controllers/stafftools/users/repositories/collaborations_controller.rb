# typed: true
# frozen_string_literal: true

class Stafftools::Users::Repositories::CollaborationsController < StafftoolsController
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
    repos = this_user.member_repositories.order(:name).paginate(page: current_page)

    invites = if current_page == 1
      this_user.received_repository_invitations.includes(:repository)
    else
      []
    end

    render(
      "stafftools/users/repositories/collaborations/index",
      locals: { repos: repos, invites: invites },
    )
  end
end
