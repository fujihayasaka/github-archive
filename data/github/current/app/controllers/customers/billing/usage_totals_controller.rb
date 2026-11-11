# typed: strict
# frozen_string_literal: true

class Customers::Billing::UsageTotalsController < Customers::BillingController
  include Billing::UsageTotalsDependency

  depends_on_clusters ApplicationRecord::Collab,
                      ApplicationRecord::Configurations,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Mysql1,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::Mysql5,
                      ApplicationRecord::NotificationsEntries,
                      ApplicationRecord::Billing


  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  sig { void }
  def show
    render_usage_totals_data(this_entity: this_entity)
  end
end
