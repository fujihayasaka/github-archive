# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::AiUsageController < Stafftools::Businesses::BillingController
  include ::Billing::AiUsageDependency

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
    T.bind(self, Stafftools::Businesses::Billing::AiUsageController)
    ensure_ai_usage_enabled(current_user: current_user)
  end

  def index
    respond_with_ai_usage(entity: this_business, is_stafftools_route: true)
  end
end
