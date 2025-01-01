# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::FiscalHostsController < Stafftools::SponsorsController
  before_action :sponsors_listing_required, except: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  LISTINGS_PER_PAGE = 30

  def index
    fiscal_host_listings = SponsorsListing.fiscal_hosts
      .includes(sponsorable: :profile)
      .paginate(page: current_page, per_page: LISTINGS_PER_PAGE)
    fiscal_host_org_logins = fiscal_host_listings.map(&:sponsorable_login)
    counts_by_fiscal_host_login = SponsorsListing
      .fiscal_host_usage_counts(fiscal_host_org_logins)

    render "stafftools/sponsors/fiscal_hosts/index", locals: {
      fiscal_host_listings: fiscal_host_listings,
      counts_by_fiscal_host_login: counts_by_fiscal_host_login,
    }
  end
end
