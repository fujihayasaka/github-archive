# typed: strict
# frozen_string_literal: true

class Customers::Billing::PremiumRequestsUsageController < Customers::BillingController
  include ::Billing::PremiumRequestsUsageDependency

  T.unsafe(self).react_bundle_name = "billing-app"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:index]

  before_action -> do
    T.bind(self, Customers::Billing::PremiumRequestsUsageController)
    ensure_pru_page_enabled(entity: this_entity)
  end

  sig { void }
  def index
    add_client_feature_flag([:billing_show_top_100_users_usage_table], entity: this_entity)
    render_premium_requests_usage(entity: this_entity, current_user: current_user)
  end
end
