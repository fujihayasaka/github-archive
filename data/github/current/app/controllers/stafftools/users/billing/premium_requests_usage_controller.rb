# typed: strict
# frozen_string_literal: true

class Stafftools::Users::Billing::PremiumRequestsUsageController < Stafftools::Users::BillingController
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
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    only: [:index]

  before_action -> do
    T.bind(self, Stafftools::Users::Billing::PremiumRequestsUsageController)
    ensure_pru_page_enabled(entity: this_user)
  end

  sig { void }
  def index
    add_client_feature_flag([:billing_show_top_100_users_usage_table], entity: this_user)
    render_premium_requests_usage(entity: this_user, is_stafftools_route: true, current_user: T.must(current_user))
  end
end
