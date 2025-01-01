# typed: strict
# frozen_string_literal: true

class Orgs::Sponsorings::BillingOptionsController < Orgs::Sponsorings::InvoicedBilling::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  sig { void }
  def show
    render "orgs/sponsorings/billing_options/show"
  end
end
