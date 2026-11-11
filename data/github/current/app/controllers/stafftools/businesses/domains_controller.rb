# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::DomainsController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    domains = this_business.verifiable_domains.paginate(page: params[:page], per_page: 10)
    render "stafftools/businesses/domains/index", locals: {
      business: this_business, verifiable_domains: domains
    }
  end
end
