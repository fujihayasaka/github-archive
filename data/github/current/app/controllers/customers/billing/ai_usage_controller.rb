# typed: strict
# frozen_string_literal: true

class Customers::Billing::AiUsageController < Customers::BillingController
  include ::Billing::AiUsageDependency

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
    only: [:index]

  before_action -> do
    T.bind(self, Customers::Billing::AiUsageController)
    ensure_ai_usage_enabled(current_user: current_user)
  end

  sig { void }
  def index
    respond_with_ai_usage(entity: this_entity)
  end
end
