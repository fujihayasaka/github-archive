# typed: strict
# frozen_string_literal: true

class Customers::Billing::AiUsageController < Customers::BillingController
  include ::Billing::AiUsageDependency

  T.unsafe(self).react_bundle_name = "billing-app"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Configurations,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Repositories,
    only: [:index]

  before_action -> do
    T.bind(self, Customers::Billing::AiUsageController)
    ensure_ai_usage_enabled(entity: this_entity)
  end

  before_action :ensure_cfi_access

  sig { void }
  def index
    render_ai_usage(entity: this_entity, current_user: current_user)
  end

  private

  sig { void }
  def ensure_cfi_access
    return unless individual_path?

    copilot_user = Copilot::User.new(current_user)
    render_404 unless copilot_user.has_cfi_access?
  end
end
