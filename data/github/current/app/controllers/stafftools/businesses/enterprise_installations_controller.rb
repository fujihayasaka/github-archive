# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::EnterpriseInstallationsController < Stafftools::Businesses::BusinessBaseController
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
    installations = this_business
      .enterprise_installations
      .for_query(params[:query])
      .order("enterprise_installations.host_name asc")
      .paginate(page: current_page, per_page: DEFAULT_PAGE_SIZE)

    render "stafftools/businesses/enterprise_installations/index", locals: {
      enterprise_installations: installations,
    }
  end
end
