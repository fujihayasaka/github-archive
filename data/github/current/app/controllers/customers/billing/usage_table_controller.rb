# typed: strict
# frozen_string_literal: true

class Customers::Billing::UsageTableController < Customers::BillingController
  include Billing::UsageTable
  T.unsafe(self).react_bundle_name = "billing-app"

  depends_on_clusters ApplicationRecord::Billing,
                      ApplicationRecord::Collab,
                      ApplicationRecord::Configurations,
                      ApplicationRecord::Copilot,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Mysql1,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::Mysql5,
                      ApplicationRecord::NotificationsEntries,
                      ApplicationRecord::Repositories,
                      only: [:index]

  sig { void }
  def index
    render_usage_table_data(this_entity: this_entity)
  end
end
