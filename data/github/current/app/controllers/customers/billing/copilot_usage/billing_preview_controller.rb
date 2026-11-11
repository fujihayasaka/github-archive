# typed: strict
# frozen_string_literal: true

class Customers::Billing::CopilotUsage::BillingPreviewController < Customers::BillingController
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
    only: [:index]

  sig { void }
  def index
    render_billing_preview(this_entity: this_entity)
  end
end
