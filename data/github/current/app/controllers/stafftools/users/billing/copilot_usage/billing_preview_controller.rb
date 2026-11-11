# typed: true
# frozen_string_literal: true

class Stafftools::Users::Billing::CopilotUsage::BillingPreviewController < Stafftools::Users::BillingController
  include Billing::Platform::Api::Utils
  include Billing::CopilotBillingPreviewDependency

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
    render_billing_preview(this_entity: this_entity, is_stafftools_route: true)
  end
end
