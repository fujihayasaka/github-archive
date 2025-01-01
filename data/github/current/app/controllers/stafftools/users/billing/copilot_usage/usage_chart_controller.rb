# typed: strict
# frozen_string_literal: true

class Stafftools::Users::Billing::CopilotUsage::UsageChartController < Stafftools::Users::BillingController
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
    render_usage_chart_data(this_entity: this_entity, is_stafftools_route: true, copilot_usage: true)
  end
end
