# typed: true
# frozen_string_literal: true

class Orgs::Settings::SpendingLimitController < Orgs::Controller
  before_action :login_required
  before_action :ensure_current_organization_for_billing
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :billing_access_required
  before_action :ensure_billing_enabled
  before_action only: :create do
    T.bind(self, Orgs::Settings::SpendingLimitController)
    check_trade_compliance(
      target: current_organization_for_member_or_billing,
      redirect_url: settings_org_billing_url(current_organization_for_member_or_billing),
      feature_type: :cost_management,
      sdn_redirect: true
    )
  end

  def create
    owner = current_organization_for_member_or_billing
    return render_404 unless Billing::Budget.configurable?(owner)
    budget_group = params[:budget_group]
    return render_404 unless Billing::Budget.valid_budget_group?(budget_group)

    if !owner.invoiced? && !owner.has_valid_payment_method?
      flash[:error] = "You can’t increase the spending limits until you set up a valid payment method"
      redirect_to :back
      return
    end

    budget = owner.budget_for(group: budget_group)
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

    redirect_to :back
  end
end
