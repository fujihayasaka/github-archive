# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::CopilotUsage::UsageTableController < Stafftools::Businesses::BillingController
  include Billing::PremiumRequestsUsageDependency
  include Billing::UsageTable

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  before_action -> do
    T.bind(self, Stafftools::Businesses::Billing::CopilotUsage::UsageTableController)
    ensure_pru_page_enabled(entity: this_business)
  end

  def index
    render_copilot_usage_table_data(this_entity: this_business, is_stafftools_route: true, page: params[:page])
  end
end
