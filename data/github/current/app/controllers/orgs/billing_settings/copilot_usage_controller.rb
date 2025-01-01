# typed: true
# frozen_string_literal: true

class Orgs::BillingSettings::CopilotUsageController < Orgs::Controller
  before_action :login_required
  before_action :org_billing_management_only
  before_action :ensure_billing_enabled
  before_action :ensure_feature_enabled

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
    only: [:show]

  def show
    view = ::BillingSettings::ProductUsageView.new(account: organization, current_user: current_user)
    copilot_monthly_usage = view.client.list_product_usage(
      view.billable_owner.current_metered_billing_cycle_starts_at,
      product_names: [Billing::Api::ClientWrapper::MEUSE_PRODUCT_NAMES[:copilot]]
    )

    render(Billing::Settings::CopilotForBusiness::UsageBodyComponent.new(
      account: view.account,
      copilot_monthly_usage: copilot_monthly_usage,
      show_spending: !organization.delegate_billing_to_business?,
    ), layout: false)
  end

  private

  memoize def organization
    current_organization_for_member_or_billing
  end

  def ensure_feature_enabled
    render_404 unless Copilot::Organization.new(organization).has_copilot_for_business?
  end
end
