# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::PremiumRequestsUsageController < Stafftools::Businesses::BillingController
  include ::Billing::PremiumRequestsUsageDependency

  T.unsafe(self).react_bundle_name = "billing-app"

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Ballast,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    only: [:index]

  before_action -> do
    T.bind(self, Stafftools::Businesses::Billing::PremiumRequestsUsageController)
    ensure_pru_page_enabled(entity: this_business)
  end

  def index
    add_client_feature_flag([:billing_show_top_100_users_usage_table], entity: this_business)
    add_client_feature_flag([:show_billing_pru_progress_bars], entity: this_business)
    render_premium_requests_usage(entity: this_business, is_stafftools_route: true, current_user: T.must(current_user))
  end
end
