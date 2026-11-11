# typed: strict
# frozen_string_literal: true

class Stafftools::Users::Billing::CopilotUsage::UsageCardController < Stafftools::Users::BillingController
  include Billing::Platform::Api::Utils
  include Billing::CopilotUsageCardDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Iam,
    ApplicationRecord::Ballast,
    only: [:index]

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  sig { void }
  def index
    render_usage_card_data(this_entity: this_entity, is_stafftools_route: true)
  end
end
