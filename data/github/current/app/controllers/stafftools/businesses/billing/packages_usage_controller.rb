# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::PackagesUsageController < Stafftools::Businesses::BillingController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    render(Billing::Settings::Packages::PackagesUsageComponent.new(
      account: this_business,
      spending_limit_enabled: ::Billing::Budget.configurable?(this_business)),
      layout: false)
  end
end
