# typed: strict
# frozen_string_literal: true

class Businesses::Billing::CopilotUsage::UsageCardController < Businesses::BillingsController
  include Billing::Platform::Api::Utils
  include Billing::CopilotUsageCardDependency

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
    render_usage_card_data(this_entity: this_business, is_stafftools_route: false)
  end
end
