# typed: true
# frozen_string_literal: true

class BillingSettings::UsageNotificationsController < ApplicationController
  include OrganizationsHelper

  before_action :login_required
  before_action :ensure_billing_enabled

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:show]

  def show
    account = current_organization_for_member_or_billing || current_user
    return render_404 if account == current_user && current_user.is_enterprise_managed?
    view = BillingSettings::ProductUsageView.new(account: account, current_user: current_user)

    render partial: "billing_settings/usage_notification", collection: view.usage_threshold_banners, as: :usage_threshold_banner, locals: { spending_limit_path: view.spending_limit_path, account: account, use_budgets: false }
  end
end
