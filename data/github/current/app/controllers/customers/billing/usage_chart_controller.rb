# typed: strict
# frozen_string_literal: true

class Customers::Billing::UsageChartController < Customers::BillingController
  include Businesses::Billing::Concerns::UsageChart

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
    render_usage_chart_data(this_entity: this_organization, is_stafftools_route: false)
  end
end
