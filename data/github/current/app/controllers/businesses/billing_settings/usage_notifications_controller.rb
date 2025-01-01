# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/ControllersShouldHaveTests
class Businesses::BillingSettings::UsageNotificationsController < Businesses::BusinessController
  # rubocop:enable GitHub/ControllersShouldHaveTests
  before_action :ensure_billing_enabled
  before_action :business_access_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    only: [:show]

  def show
    view = Businesses::BillingSettings::ProductUsageView.new(current_user: current_user, business: this_business)
    spending_limit_path = settings_billing_tab_enterprise_path(this_business, :cost_management)
    use_budgets = FeatureFlag.vexi.enabled?(:ghe_spending_limits, this_business, default: false)

    render partial: "billing_settings/usage_notification", collection: view.usage_threshold_banners, as: :usage_threshold_banner, locals: { spending_limit_path: spending_limit_path, account: current_user, use_budgets: use_budgets }
  end
end
