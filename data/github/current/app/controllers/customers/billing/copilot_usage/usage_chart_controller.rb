# typed: strict
# frozen_string_literal: true

class Customers::Billing::CopilotUsage::UsageChartController < Customers::BillingController
  include Billing::Platform::Api::Utils
  include Billing::UsageChartDependency

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
    only: [:index]

  sig { void }
  def index
    render_usage_chart_data(this_entity: this_entity, is_stafftools_route: false, copilot_usage: true)
  end
end
