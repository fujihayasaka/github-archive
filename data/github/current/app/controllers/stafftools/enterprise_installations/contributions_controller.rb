# typed: true
# frozen_string_literal: true

class Stafftools::EnterpriseInstallations::ContributionsController < StafftoolsController
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
    render "stafftools/enterprise_installations/contributions",
      locals: {
        installation: this_enterprise_installation,
        contributions: this_enterprise_installation
          .enterprise_contributions.order(updated_at: :desc)
          .group("user_id")
          .paginate(page: current_page)
      }
  end
end
