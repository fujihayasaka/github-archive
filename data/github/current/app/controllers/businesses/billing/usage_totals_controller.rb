# typed: strict
# frozen_string_literal: true

class Businesses::Billing::UsageTotalsController < Businesses::BillingsController
  T.unsafe(self).react_bundle_name = "billing-app"
  include Billing::UsageTotalsDependency

  depends_on_clusters ApplicationRecord::Collab,
                      ApplicationRecord::Configurations,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Mysql1,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::Mysql5,
                      ApplicationRecord::NotificationsEntries,
                      ApplicationRecord::Billing

  sig { void }
  def show
    render_usage_totals_data(this_entity: this_business)
  end
end
