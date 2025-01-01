# typed: true
# frozen_string_literal: true

class Orgs::Settings::UsageNotificationSettingsController < Orgs::Controller
  before_action :login_required
  before_action :ensure_current_organization
  before_action :organization_admin_required
  before_action :ensure_trade_restrictions_allows_org_settings_access

  def create
    owner = current_organization_for_member_or_billing
    return render_404 unless Billing::Budget.configurable?(owner)
    notification_params = usage_notification_params
    budget_group = notification_params[:budget_group]
    return render_404 unless Billing::Budget.valid_budget_group?(budget_group)

    budget = owner.budget_for(group: budget_group)
    status = budget.configure_notifications(
      included_usage_notification: notification_params[:included_usage_notification],
      paid_usage_notification: notification_params[:paid_usage_notification],
    )
    if request.xhr?
      head status ? 200 : 400
    else
      if !status
        flash[:error] = "Unable to update notification settings."
      end
      redirect_to settings_org_billing_tab_path(owner, tab: "spending_limit")
    end
  end

  private

  def usage_notification_params
    params.permit(:authenticity_token, :organization_id, :budget_group,
                  :included_usage_notification, :paid_usage_notification)
  end
end
