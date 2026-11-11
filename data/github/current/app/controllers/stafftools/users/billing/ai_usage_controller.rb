# typed: strict
# frozen_string_literal: true

class Stafftools::Users::Billing::AiUsageController < Stafftools::Users::BillingController
  include ::Billing::AiUsageDependency

  T.unsafe(self).react_bundle_name = "billing-app"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Authnd,
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

  sig { void }
  def index
    render_ai_usage(entity: this_user, current_user: current_user, is_stafftools_route: true)
  end
end
