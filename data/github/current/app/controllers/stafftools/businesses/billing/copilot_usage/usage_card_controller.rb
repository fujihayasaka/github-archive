# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::CopilotUsage::UsageCardController < Stafftools::Businesses::BillingController
  include Billing::CopilotUsageCardDependency
  include Billing::PremiumRequestsUsageDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::Ballast,
    only: [:index]

  before_action -> do
    T.bind(self, Stafftools::Businesses::Billing::CopilotUsage::UsageCardController)
    ensure_pru_page_enabled(entity: this_business)
  end

  def index
    render_usage_card_data(this_entity: this_business, is_stafftools_route: true)
  end
end
