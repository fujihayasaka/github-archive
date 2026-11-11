# typed: true
# frozen_string_literal: true

class Stafftools::EnterpriseInstallations::UserAccountsUploadsController < StafftoolsController
  layout "layouts/stafftools/enterprise_installation"

  depends_on_clusters \
    ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot, only: [:index], optional: true

  def index
    render "stafftools/enterprise_installations/user_accounts_uploads",
      locals: {
        installation: this_enterprise_installation,
        uploads: this_enterprise_installation
          .user_accounts_uploads
          .order(created_at: :desc)
          .paginate(page: current_page)
      }
  end

  def update
    SyncEnterpriseServerUserAccountsJob.perform_later(
      this_enterprise_installation.owner,
      this_enterprise_installation,
      params[:upload_id],
      ::User.staff_user
    )
    redirect_to \
      stafftools_enterprise_installation_user_accounts_uploads_path(this_enterprise_installation),
        notice: "Enterprise Server license usage import job enqueued."
  end
end
