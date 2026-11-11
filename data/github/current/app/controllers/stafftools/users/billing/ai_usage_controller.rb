# typed: strict
# frozen_string_literal: true

class Stafftools::Users::Billing::AiUsageController < Stafftools::Users::BillingController
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
    ApplicationRecord::Ballast,
    only: [:index]

  before_action -> do
    T.bind(self, Stafftools::Users::Billing::AiUsageController)
    ensure_ai_usage_enabled(current_user: current_user)
  end

  sig { void }
  def index
    respond_with_ai_usage(entity: this_user, is_stafftools_route: true)
  end
end
