# typed: true
# frozen_string_literal: true

class Stafftools::Users::Billing::BillableRollbacksController < StafftoolsController
  include Stafftools::BillingPermissionCheck
  include Stafftools::Users::ControllerLayoutMethods
  include MarketingMethods

  layout :billing_layout

  before_action :ensure_user_exists

  # Active Sponsorship and Billing::SubscriptionItem record but cancelled subscriptions in Zuora.
  # Running a rollback on their plan subscription should get things back in sync.
  def create
    plan_subscription = if params[:purpose] == "sponsors"
      this_user.sponsors_plan_subscription
    else
      this_user.plan_subscription
    end
    if plan_subscription
      Billing::Zuora::BillableRollback.perform(plan_subscription, params[:rollback_reason])
      adjective = plan_subscription.purpose_description.capitalize
      flash[:notice] = "#{adjective} plan subscription cancelled for #{this_user}"
    else
      flash[:error] = "No such plan subscription exists for #{this_user}"
    end
    redirect_to billing_stafftools_user_path(this_user)
  end
end
