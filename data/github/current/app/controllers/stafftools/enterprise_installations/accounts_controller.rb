# typed: true
# frozen_string_literal: true

class Stafftools::EnterpriseInstallations::AccountsController < StafftoolsController
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
    render "stafftools/enterprise_installations/accounts",
      locals: {
        installation: this_enterprise_installation,
        accounts: this_enterprise_installation
          .user_accounts
          .includes(:emails)
          .order(login: :asc)
          .paginate(page: current_page)
      }
  end
end
