# typed: true
# frozen_string_literal: true

class Businesses::MeteredBillingCostsController < Businesses::BusinessController
  before_action :ensure_billing_enabled
  before_action :business_access_required

  def update
    return render_404 unless Billing::Budget.configurable?(this_business)
    return render_404 unless Billing::Budget.valid_budget_group?(params[:budget_group])

    budget = this_business.budget_for(group: params[:budget_group])
    budget.configure(
      enforce_spending_limit: params[:enforce_spending_limit] == "true",
      limit: params[:spending_limit],
    )

    if budget.errors.any?
      if budget.errors[:tiered_spending].present?
        flash[:error] = budget.errors[:tiered_spending].first
      else
        flash[:error] = "Unable to set a spending limit. Please check your payment method and limit"
      end
    else
      flash[:notice] = "Spending limit configuration has been updated"
    end

    redirect_back fallback_location: settings_billing_enterprise_path(this_business)
  end

  def usage_notification_settings # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless Billing::Budget.configurable?(this_business)
    notification_params = usage_notification_params
    budget_group = notification_params[:budget_group]
    return render_404 unless Billing::Budget.valid_budget_group?(budget_group)

    budget = this_business.budget_for(group: budget_group)
    status = budget.configure_notifications(
      included_usage_notification: notification_params[:included_usage_notification],
      paid_usage_notification: notification_params[:paid_usage_notification],
    )
    if request.xhr?
      head status ? :ok : :bad_request
    else
      if !status
        flash[:error] = "Unable to update notification settings."
      end
      redirect_back fallback_location: settings_billing_enterprise_path(this_business)
    end
  end

  def usage_notification_params # rubocop:todo GitHub/UseRestfulActions
    params.permit(:authenticity_token, :slug, :budget_group,
                  :included_usage_notification, :paid_usage_notification)
  end
end
