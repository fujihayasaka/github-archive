# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::SponsorshipsController < Stafftools::Businesses::BillingController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render "stafftools/billing/sponsorships/index", locals: {
      organizations_sponsorships: organizations_sponsorships,
    }
  end

  private

  memoize def organizations_sponsorships
    this_business.active_organizations_sponsorships
  end
end
