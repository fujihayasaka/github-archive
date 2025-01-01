# typed: true
# frozen_string_literal: true

# Controller getting organizations usage notification
class Orgs::BillingSettings::UsageNotificationsController < Orgs::Controller
  before_action :login_required
  before_action :org_billing_management_only
  before_action :ensure_billing_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  def show
    org = current_organization_for_member_or_billing
    view = BillingSettings::ProductUsageView.new(account: org, current_user: current_user)

    spending_limit_path = if org.delegate_billing_to_business?
      ""
    else
      view.spending_limit_path
    end

    render partial: "billing_settings/usage_notification", collection: view.usage_threshold_banners, as: :usage_threshold_banner, locals: { spending_limit_path: spending_limit_path, account: org, use_budgets: false }
  end

  private

  def ensure_billing_enabled
    return render_404 unless GitHub.billing_enabled?
  end
end
