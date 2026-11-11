# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::Billing::CopilotUsage::BillingPreviewController < Stafftools::Businesses::BillingController
  include Billing::CopilotBillingPreviewDependency

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

  def index
    render_billing_preview(this_entity: this_business, is_stafftools_route: true)
  end
end
