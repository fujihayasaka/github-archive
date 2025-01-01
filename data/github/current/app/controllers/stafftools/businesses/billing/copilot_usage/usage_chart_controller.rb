# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::CopilotUsage::UsageChartController < Stafftools::Businesses::BillingController
  include Billing::UsageChartDependency
  include Billing::PremiumRequestsUsageDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  before_action -> do
    T.bind(self, Stafftools::Businesses::Billing::CopilotUsage::UsageChartController)
    ensure_pru_page_enabled(entity: this_business)
  end

  sig { void }
  def index
    render_usage_chart_data(this_entity: this_business, is_stafftools_route: true, copilot_usage: true)
  end
end
